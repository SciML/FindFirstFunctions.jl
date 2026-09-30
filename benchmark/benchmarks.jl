# AirspeedVelocity-driven benchmark suite. Each `SUITE[...]` entry is a
# `BenchmarkGroup` (or `@benchmarkable`) that AirspeedVelocity will time on
# both the PR branch and the base branch, then diff. Keep individual cells
# fast (< 200 ms target) so the CI run finishes in a few minutes.

using BenchmarkTools
using FindFirstFunctions
using StableRNGs

const SUITE = BenchmarkGroup()

# Helper: build a sorted Float64 vector with the given pattern.
function _make_v(kind, n, seed = 2026)
    rng = StableRNG(seed)
    return if kind === :uniform
        collect(range(0.0, Float64(n); length = n))
    elseif kind === :logspaced
        collect(exp.(range(0.0, log(1.0e6); length = n)))
    elseif kind === :random_sorted
        sort!(rand(rng, n) .* n)
    else
        error("unknown v kind $kind")
    end
end

function _make_q(v, m, kind, seed = 2027)
    rng = StableRNG(seed)
    return if kind === :dense
        collect(range(first(v), last(v); length = m))
    elseif kind === :sparse
        sort!(first(v) .+ rand(rng, m) .* (last(v) - first(v)))
    elseif kind === :clustered
        j = max(1, length(v) ÷ 4)
        lo = v[j]
        hi = v[min(j + 1, length(v))]
        span = hi - lo
        sort!(lo .+ rand(rng, m) .* max(span, 1.0))
    else
        error("unknown q kind $kind")
    end
end

# ---------------------------------------------------------------------------
# Per-strategy single-query micro-benchmarks (Int64, n=1024, hint near answer)
# ---------------------------------------------------------------------------
SUITE["per_query"] = BenchmarkGroup()
let v = collect(Int64, 1:1024), x = Int64(500), hint = 480
    for (name, strategy) in [
            ("LinearScan", LinearScan()),
            ("SIMDLinearScan", SIMDLinearScan()),
            ("BracketGallop", BracketGallop()),
            ("ExpFromLeft", ExpFromLeft()),
            ("InterpolationSearch", InterpolationSearch()),
            ("BinaryBracket", BinaryBracket()),
            ("Auto", Auto()),
        ]
        SUITE["per_query"][name] = @benchmarkable(
            searchsorted_last($strategy, $v, $x, $hint),
            evals = 1, samples = 200,
        )
    end
end

# ---------------------------------------------------------------------------
# Batched in-place benchmarks: a small grid of (v_kind, q_kind, n, m).
# Auto vs hand-picked strategies, plus the queries_sorted = true fast path.
# ---------------------------------------------------------------------------
# Warm-started walk: each query's hint is the previous answer, and consecutive
# queries move by a fraction of an interval (the interpolation-lookup pattern).
# BracketGallop's hit fast path is what this cell measures; LinearScan is the
# reference for a hint that is right most of the time.
SUITE["warm_walk"] = BenchmarkGroup()
let v = _make_v(:random_sorted, 100_000), rng = StableRNG(7), nq = 4096
    xs = Vector{Float64}(undef, nq)
    x = v[1]
    for k in 1:nq
        i = clamp(searchsortedlast(v, x), 1, length(v) - 1)
        x = clamp(x + (rand(rng) < 0.01 ? (rand(rng) - 0.5) * 200 : rand(rng) * 0.35) * (v[i + 1] - v[i]), v[1], v[end])
        xs[k] = x
    end
    function walk(strategy, v, xs)
        idx = 1; s = 0
        for x in xs
            idx = searchsorted_last(strategy, v, x, idx); s += idx
        end
        return s
    end
    for (name, strategy) in (("BracketGallop", BracketGallop()), ("LinearScan", LinearScan()), ("Auto", Auto()))
        SUITE["warm_walk"][name] = @benchmarkable($walk($strategy, $v, $xs))
    end
end

SUITE["batched"] = BenchmarkGroup()
for v_kind in (:uniform, :logspaced, :random_sorted),
        q_kind in (:dense, :sparse, :clustered),
        (n, m) in ((1024, 64), (16_384, 256), (65_536, 4096))

    v = _make_v(v_kind, n)
    q = _make_q(v, m, q_kind)
    out = Vector{Int}(undef, m)

    key = "$(v_kind)/$(q_kind)/n=$n/m=$m"
    grp = BenchmarkGroup()
    grp["Auto"] = @benchmarkable(
        FindFirstFunctions.searchsortedlast!($out, $v, $q; strategy = Auto()),
        evals = 1, samples = 50,
    )
    grp["Auto+sorted"] = @benchmarkable(
        FindFirstFunctions.searchsortedlast!(
            $out, $v, $q;
            strategy = Auto(), queries_sorted = true,
        ),
        evals = 1, samples = 50,
    )
    grp["Auto+props"] = @benchmarkable(
        FindFirstFunctions.searchsortedlast!(
            $out, $v, $q;
            strategy = Auto(SearchProperties($v)),
        ),
        evals = 1, samples = 50,
    )
    SUITE["batched"][key] = grp
end

# ---------------------------------------------------------------------------
# SearchProperties construction cost (probe + NaN scan on Float64)
# ---------------------------------------------------------------------------
SUITE["props_construct"] = BenchmarkGroup()
for (name, v) in [
        ("uniform_64k", collect(range(0.0, 100.0; length = 65_536))),
        ("logspaced_64k", collect(exp.(range(0.0, log(1.0e6); length = 65_536)))),
        ("int64_64k", collect(Int64, 1:65_536)),
    ]
    SUITE["props_construct"][name] = @benchmarkable(
        SearchProperties($v),
        evals = 1, samples = 50,
    )
end

# ---------------------------------------------------------------------------
# Equality search comparison
# ---------------------------------------------------------------------------
SUITE["equality"] = BenchmarkGroup()
let v = collect(Int64, 1:65_536), x = Int64(50_000)
    SUITE["equality"]["findequal_BinaryBracket"] = @benchmarkable(
        findequal(BinaryBracket(), $v, $x),
        evals = 1, samples = 200,
    )
    SUITE["equality"]["findequal_BisectThenSIMD"] = @benchmarkable(
        findequal(BisectThenSIMD(), $v, $x),
        evals = 1, samples = 200,
    )
    SUITE["equality"]["findfirstsortedequal"] = @benchmarkable(
        findfirstsortedequal($x, $v),
        evals = 1, samples = 200,
    )
end

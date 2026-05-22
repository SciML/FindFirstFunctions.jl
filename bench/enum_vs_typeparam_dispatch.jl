# Bench: enum-tagged dispatch (`search_last(KIND_X, ...)`) vs the legacy
# multimethod-on-struct dispatch (`Base.searchsortedlast(::S(), ...)`).
#
# Confirms the v3 claim: the runtime `if/elseif` over a `StrategyKind`
# value adds ~0 ns of overhead because it is well-predicted in hot loops,
# the kernel bodies inline, and the return type stays type-stable.
#
# Usage: `julia +1.11 --project=bench bench/enum_vs_typeparam_dispatch.jl`
# (or run from the repo root via `Pkg.activate("bench")`).

using BenchmarkTools, FindFirstFunctions, Printf, StableRNGs

const RNG_SEED = 9023

# Representative grid sizes. Small (cache-resident), medium, large.
const GRID_SIZES = (16, 256, 4_096, 65_536)

# Strategies under test — only the ones where the enum dispatch matters.
# `BinaryBracket` and `InterpolationSearch` ignore the hint, so the per-call
# overhead surface is smaller; still useful to confirm parity.
const STRATEGIES = (
    (BracketGallop(), KIND_BRACKET_GALLOP, "BracketGallop"),
    (LinearScan(), KIND_LINEAR_SCAN, "LinearScan"),
    (ExpFromLeft(), KIND_EXP_FROM_LEFT, "ExpFromLeft"),
    (InterpolationSearch(), KIND_INTERPOLATION_SEARCH, "InterpolationSearch"),
    (BinaryBracket(), KIND_BINARY_BRACKET, "BinaryBracket"),
)

# Helper: median time in ns for one call configuration.
function bench_ns(f, args...; samples = 500)
    b = @benchmark $f($(args)...) samples = samples evals = 50 seconds = 2
    return BenchmarkTools.minimum(b).time
end

# Hot-loop variant: total elapsed time across `m` queries, normalized to ns/q.
# This is the realistic per-call cost — the per-iteration `if/elseif` over
# the enum value is the workload we're measuring.
function hot_loop_legacy(strategy, v, queries, hints)
    s = 0
    @inbounds for i in eachindex(queries)
        s += searchsortedlast(strategy, v, queries[i], hints[i])
    end
    return s
end

function hot_loop_kind(kind, v, queries, hints)
    s = 0
    @inbounds for i in eachindex(queries)
        s += search_last(kind, v, queries[i], hints[i])
    end
    return s
end

function build_workload(n, rng)
    v = sort!(rand(rng, n))
    # Query positions: a mix of in-vector and out-of-range. Each query
    # comes with a hint that's ±3 of the true answer (the "good hint" regime
    # where hint-using strategies shine).
    m = max(64, n ÷ 16)
    queries = sort!(rand(rng, m))
    truths = [searchsortedlast(v, q) for q in queries]
    hints = [clamp(t + rand(rng, -3:3), 1, n) for t in truths]
    return (v, queries, hints)
end

function main()
    rng = StableRNG(RNG_SEED)
    rows = Any[]
    for n in GRID_SIZES
        v, queries, hints = build_workload(n, rng)
        for (s, kind, name) in STRATEGIES
            t_legacy = bench_ns(hot_loop_legacy, s, v, queries, hints)
            t_kind = bench_ns(hot_loop_kind, kind, v, queries, hints)
            # Per-query overhead numbers.
            m = length(queries)
            ns_legacy = t_legacy / m
            ns_kind = t_kind / m
            delta = ns_kind - ns_legacy
            pct = delta / ns_legacy * 100
            push!(
                rows,
                (
                    n = n, strategy = name,
                    legacy_ns_q = round(ns_legacy; digits = 1),
                    enum_ns_q = round(ns_kind; digits = 1),
                    delta_ns_q = round(delta; digits = 2),
                    delta_pct = round(pct; digits = 1),
                ),
            )
        end
    end
    @printf "%-8s %-22s %-12s %-12s %-12s %s\n" "n" "strategy" "legacy ns/q" "enum ns/q" "Δ ns/q" "Δ %"
    println("-"^80)
    for r in rows
        @printf "%-8d %-22s %-12.2f %-12.2f %-12.2f %.1f\n" r.n r.strategy r.legacy_ns_q r.enum_ns_q r.delta_ns_q r.delta_pct
    end
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

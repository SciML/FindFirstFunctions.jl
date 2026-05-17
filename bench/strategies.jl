"""
Benchmark sweep for the SearchStrategy types in FindFirstFunctions.

Run from the repo root:

    julia --project=bench bench/strategies.jl                # default fast sweep
    MODE=full julia --project=bench bench/strategies.jl      # full sweep
    MODE=spacing julia --project=bench bench/strategies.jl   # focused: spacing variety
    MODE=ratio   julia --project=bench bench/strategies.jl   # focused: n/m crossover
    MODE=pattern julia --project=bench bench/strategies.jl   # focused: query pattern
    MODE=extreme julia --project=bench bench/strategies.jl   # focused: very sparse / very dense

Sweeps over:

  - knot count `n`         (16 .. 1_000_000 in the full sweep)
  - query count `m`        (1 .. 4n in the full sweep)
  - knot spacing           (10 spacings, see KNOT_SPACINGS below)
  - query pattern          (8 patterns, see QUERY_PATTERNS below)
  - strategy               (LinearScan, BracketGallop, ExpFromLeft,
                            InterpolationSearch, BinaryBracket, Auto)

Emits a Markdown table per sub-sweep so the regimes where each strategy wins
are easy to read off, plus a "best/auto" column that flags cells where the
heuristic doesn't land on the actual best strategy.
"""

using BenchmarkTools
using StableRNGs
using Printf
using FindFirstFunctions: LinearScan, BracketGallop, ExpFromLeft,
    InterpolationSearch, BinaryBracket, Auto, SearchStrategy,
    searchsortedlast!, searchsortedfirst!

const RNG = StableRNG(0xfaceb00c)

# ---------------------------------------------------------------------------
# Knot-generation helpers
# ---------------------------------------------------------------------------

knots_uniform(n) = collect(range(0.0, 10.0; length = n))
knots_log(n) = collect(exp.(range(log(0.1), log(100.0); length = n)))
function knots_jittered(n; rel = 0.3)
    base = collect(range(0.0, 10.0; length = n))
    n < 2 && return base
    step = base[2] - base[1]
    return sort!(base .+ (rand(RNG, n) .- 0.5) .* rel .* step)
end
knots_random(n) = sort!(rand(RNG, n) .* 10.0)
function knots_two_scale(n)
    # Half the knots packed near 0..1, half spread over 1..1000
    n1 = n ÷ 2
    n2 = n - n1
    return sort!(vcat(rand(RNG, n1), 1.0 .+ rand(RNG, n2) .* 999.0))
end
# v_i = (i / n)^2 — quadratic spacing; dense near 0, sparse near 1.
knots_power2(n) = collect(((0:(n - 1)) ./ max(1, n - 1)) .^ 2 .* 10.0)
# v_i = sqrt(i / n) — square-root spacing; sparse near 0, dense near 1.
knots_sqrt(n) = collect(sqrt.((0:(n - 1)) ./ max(1, n - 1)) .* 10.0)
# Three flat plateaus and two jumps — many duplicate values.
function knots_plateau(n)
    chunk = max(1, n ÷ 3)
    v = vcat(fill(1.0, chunk), fill(5.0, chunk), fill(9.0, n - 2 * chunk))
    return v
end
# Bimodal: two dense clusters at 0..1 and 9..10, sparse middle.
function knots_bimodal(n)
    n1 = n ÷ 2
    n2 = n - n1
    left = sort!(rand(RNG, n1))
    right = sort!(9.0 .+ rand(RNG, n2))
    return vcat(left, right)
end
# Almost-linear with one tiny offset to defeat simple range checks.
function knots_near_linear(n)
    v = collect(range(0.0, 10.0; length = n))
    if n >= 4
        v[end - 1] += 1.0e-9
    end
    return v
end

const ALL_KNOT_SPACINGS = (
    :uniform => knots_uniform,
    :log => knots_log,
    :jittered => knots_jittered,
    :random => knots_random,
    :two_scale => knots_two_scale,
    :power2 => knots_power2,
    :sqrt => knots_sqrt,
    :plateau => knots_plateau,
    :bimodal => knots_bimodal,
    :near_linear => knots_near_linear,
)

# Fast-sweep subset
const FAST_KNOT_SPACINGS = (
    :uniform => knots_uniform,
    :log => knots_log,
    :jittered => knots_jittered,
    :random => knots_random,
    :two_scale => knots_two_scale,
)

# ---------------------------------------------------------------------------
# Query-generation helpers
# ---------------------------------------------------------------------------

function queries_uniform(t::Vector, m::Integer)
    lo, hi = first(t), last(t)
    return sort!(lo .+ (hi - lo) .* rand(RNG, m))
end

# All queries packed inside a single tiny segment in the middle of t.
function queries_dense_burst(t::Vector, m::Integer)
    n = length(t)
    i = max(1, n ÷ 2)
    lo, hi = t[i], t[min(i + 1, n)]
    return sort!(lo .+ (hi - lo) .* rand(RNG, m))
end

# 90% of queries clustered in the first 5% of t, 10% spread over the rest.
function queries_clustered_near_start(t::Vector, m::Integer)
    n = length(t)
    cutoff = max(2, n ÷ 20)
    lo1, hi1 = t[1], t[cutoff]
    lo2, hi2 = t[cutoff], t[end]
    n1 = max(1, (9 * m) ÷ 10)
    n2 = m - n1
    return sort!(
        vcat(
            lo1 .+ (hi1 - lo1) .* rand(RNG, n1),
            lo2 .+ (hi2 - lo2) .* rand(RNG, n2)
        )
    )
end

# Arithmetic progression covering the full range of t.
function queries_arithmetic(t::Vector, m::Integer)
    return collect(range(first(t), last(t); length = m))
end

# Geometric progression — gaps double as we move forward.
function queries_geometric(t::Vector, m::Integer)
    m <= 1 && return [first(t)]
    lo, hi = first(t), last(t)
    span = hi - lo
    weights = collect(0:(m - 1)) ./ (m - 1)
    geo = exp.(log(1) .+ (log(span + 1) - log(1)) .* weights) .- 1
    return lo .+ geo
end

# Bimodal: half clustered at one end of t, half at the other.
function queries_bimodal(t::Vector, m::Integer)
    lo, hi = first(t), last(t)
    n1 = m ÷ 2
    n2 = m - n1
    span = (hi - lo) * 0.1
    return sort!(
        vcat(
            lo .+ span .* rand(RNG, n1),
            hi .- span .* rand(RNG, n2)
        )
    )
end

# Same value repeated — pathological for any hint-using strategy if `v`
# has duplicates around it.
function queries_repeated(t::Vector, m::Integer)
    mid = t[max(1, length(t) ÷ 2)]
    return fill(mid, m)
end

function queries_unsorted(t::Vector, m::Integer)
    lo, hi = first(t), last(t)
    return lo .+ (hi - lo) .* rand(RNG, m)
end

const ALL_QUERY_PATTERNS = (
    :sorted_uniform => queries_uniform,
    :sorted_dense_burst => queries_dense_burst,
    :sorted_near_start => queries_clustered_near_start,
    :sorted_arithmetic => queries_arithmetic,
    :sorted_geometric => queries_geometric,
    :sorted_bimodal => queries_bimodal,
    :sorted_repeated => queries_repeated,
    :unsorted => queries_unsorted,
)

const FAST_QUERY_PATTERNS = (
    :sorted_uniform => queries_uniform,
    :sorted_dense_burst => queries_dense_burst,
    :sorted_near_start => queries_clustered_near_start,
    :unsorted => queries_unsorted,
)

# ---------------------------------------------------------------------------
# Strategies under test
# ---------------------------------------------------------------------------

const STRATEGIES = (
    "Linear" => LinearScan(),
    "Gallop" => BracketGallop(),
    "ExpFromLeft" => ExpFromLeft(),
    "InterpSearch" => InterpolationSearch(),
    "Binary" => BinaryBracket(),
    "Auto" => Auto(),
)

# ---------------------------------------------------------------------------
# Benchmark primitives
# ---------------------------------------------------------------------------

"Returns minimum-time-per-batch (ns) for the given strategy on `(v, q)`."
function bench_batch(strategy::SearchStrategy, v::Vector, q::Vector)
    out = Vector{Int}(undef, length(q))
    b = @benchmark searchsortedlast!($out, $v, $q; strategy = $strategy) samples = 20 evals = 1
    return minimum(b).time   # ns
end

function bench_base(v::Vector, q::Vector)
    out = Vector{Int}(undef, length(q))
    b = @benchmark begin
        @inbounds for k in eachindex($q)
            $out[k] = searchsortedlast($v, $q[k])
        end
    end samples = 20 evals = 1
    return minimum(b).time
end

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

function format_ns(x)
    return if isnan(x)
        " - "
    elseif x >= 1.0e6
        @sprintf("%.2f ms", x / 1.0e6)
    elseif x >= 1.0e3
        @sprintf("%.1f μs", x / 1.0e3)
    else
        @sprintf("%.0f ns", x)
    end
end

function run_sweep(; title, ns, ms, spacings, query_patterns, strategies)
    println("\n## $title\n")
    header = String[
        "spacing", "query pattern", "n", "m",
    ]
    for (name, _) in strategies
        push!(header, name)
    end
    push!(header, "base")
    push!(header, "best")
    push!(header, "best/auto")
    println("| ", join(header, " | "), " |")
    println(
        "|---|---|---|---|",
        join(("---" for _ in strategies), "|"),
        "|---|---|---|"
    )

    auto_wins = 0
    auto_losses = 0
    auto_within_20pct = 0
    rows = 0

    for (sp_name, sp_fn) in spacings
        for (qp_name, qp_fn) in query_patterns
            for n in ns
                t = sp_fn(n)
                for m in ms
                    q = qp_fn(t, m)
                    results = Dict{String, Float64}()
                    for (name, strat) in strategies
                        results[name] = bench_batch(strat, t, q)
                    end
                    results["base"] = bench_base(t, q)
                    best_name, best_t = "", Inf
                    for (name, t_) in results
                        (name == "Auto" || name == "base") && continue
                        if t_ < best_t
                            best_t = t_
                            best_name = name
                        end
                    end
                    auto_t = results["Auto"]
                    rel = auto_t / best_t
                    if rel < 0.95
                        auto_wins += 1
                    elseif rel > 1.2
                        auto_losses += 1
                    else
                        auto_within_20pct += 1
                    end
                    rows += 1

                    cols = String[
                        string(sp_name), string(qp_name),
                        string(n), string(m),
                    ]
                    for (name, _) in strategies
                        push!(cols, format_ns(results[name]))
                    end
                    push!(cols, format_ns(results["base"]))
                    push!(cols, "$(best_name) ($(format_ns(best_t)))")
                    push!(cols, @sprintf("%.2fx", rel))
                    println("| ", join(cols, " | "), " |")
                end
            end
        end
    end

    println(
        "\n**Auto verdict over $rows cells**: ",
        "$auto_within_20pct within 20% of best, ",
        "$auto_losses worse than 20% slowdown, ",
        "$auto_wins effectively-faster-than-best."
    )
    return (rows, auto_within_20pct, auto_losses, auto_wins)
end

# ---------------------------------------------------------------------------
# Pre-built sweep definitions
# ---------------------------------------------------------------------------

function fast_sweep()
    return run_sweep(
        title = "Fast sweep",
        ns = (64, 1024, 65_536),
        ms = (1, 10, 256, 4096),
        spacings = FAST_KNOT_SPACINGS,
        query_patterns = FAST_QUERY_PATTERNS,
        strategies = STRATEGIES,
    )
end

function full_sweep()
    return run_sweep(
        title = "Full sweep",
        ns = (16, 64, 256, 1024, 4096, 65_536, 262_144),
        ms = (1, 10, 64, 256, 1024, 4096),
        spacings = ALL_KNOT_SPACINGS,
        query_patterns = ALL_QUERY_PATTERNS,
        strategies = STRATEGIES,
    )
end

# Focused: vary spacing only, fix n=4096, m=512, pattern=sorted_uniform.
function sweep_spacing()
    return run_sweep(
        title = "Spacing variety (n=4096, m=512, sorted_uniform)",
        ns = (4096,),
        ms = (512,),
        spacings = ALL_KNOT_SPACINGS,
        query_patterns = (:sorted_uniform => queries_uniform,),
        strategies = STRATEGIES,
    )
end

# Focused: vary n and m on uniform data.
function sweep_ratio()
    return run_sweep(
        title = "n/m crossover (uniform, sorted_uniform)",
        ns = (16, 64, 256, 1024, 4096, 16_384, 65_536, 262_144),
        ms = (1, 4, 16, 64, 256, 1024, 4096, 16_384),
        spacings = (:uniform => knots_uniform,),
        query_patterns = (:sorted_uniform => queries_uniform,),
        strategies = STRATEGIES,
    )
end

# Focused: vary query pattern.
function sweep_pattern()
    return run_sweep(
        title = "Query patterns (n=4096, m=512, uniform)",
        ns = (4096,),
        ms = (512,),
        spacings = (:uniform => knots_uniform,),
        query_patterns = ALL_QUERY_PATTERNS,
        strategies = STRATEGIES,
    )
end

# Focused: stress edges — super sparse and super dense.
function sweep_extreme()
    # Super sparse: m=1..16 over varied n.
    # Super dense: m = 4n.
    println("\n### Super-sparse cases (small m on large n)")
    res_sparse = run_sweep(
        title = "Super sparse",
        ns = (1024, 16_384, 262_144),
        ms = (1, 4, 16),
        spacings = ALL_KNOT_SPACINGS,
        query_patterns = (
            :sorted_uniform => queries_uniform,
            :unsorted => queries_unsorted,
        ),
        strategies = STRATEGIES,
    )

    println("\n### Super-dense cases (m ≫ n)")
    res_dense = run_sweep(
        title = "Super dense",
        ns = (64, 256, 1024),
        ms = (1024, 4096, 16_384),    # m up to 256× n
        spacings = ALL_KNOT_SPACINGS,
        query_patterns = (
            :sorted_uniform => queries_uniform,
            :sorted_dense_burst => queries_dense_burst,
            :unsorted => queries_unsorted,
        ),
        strategies = STRATEGIES,
    )
    return (sparse = res_sparse, dense = res_dense)
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = get(ENV, "MODE", "fast")
    if mode == "full"
        full_sweep()
    elseif mode == "spacing"
        sweep_spacing()
    elseif mode == "ratio"
        sweep_ratio()
    elseif mode == "pattern"
        sweep_pattern()
    elseif mode == "extreme"
        sweep_extreme()
    else
        fast_sweep()
    end
end

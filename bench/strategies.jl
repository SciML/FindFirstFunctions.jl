"""
Benchmark sweep for the SearchStrategy types in FindFirstFunctions.

Run from the repo root:

    julia --project=bench bench/strategies.jl

Or with an existing environment:

    julia --project=. -e 'using Pkg; Pkg.add(["BenchmarkTools", "StableRNGs", "Printf"]); include("bench/strategies.jl")'

Sweeps over:

  - knot count `n`
  - query count `m`
  - knot spacing  (uniform, log, jittered, geometric-with-outliers)
  - query pattern (sorted-uniform, sorted-dense-burst, sorted-clustered-near-start, unsorted, single)
  - strategy      (LinearScan, BracketGallop, ExpFromLeft, InterpolationSearch, BinaryBracket, Auto)

Emits a Markdown table per sub-sweep so the regimes where each strategy wins
are easy to read off.
"""

using BenchmarkTools
using StableRNGs
using Printf
import FindFirstFunctions as FFF
using FindFirstFunctions: LinearScan, BracketGallop, ExpFromLeft,
    InterpolationSearch, BinaryBracket, Auto, SearchStrategy,
    searchsortedlast!, searchsortedfirst!

const RNG = StableRNG(0xfaceb00c)

# ---------------------------------------------------------------------------
# Knot-generation helpers
# ---------------------------------------------------------------------------

knots_uniform(n) = collect(range(0.0, 10.0; length = n))
function knots_log(n)
    return collect(exp.(range(log(0.1), log(100.0); length = n)))
end
function knots_jittered(n; rel = 0.3)
    base = collect(range(0.0, 10.0; length = n))
    step = base[2] - base[1]
    return sort!(base .+ (rand(RNG, n) .- 0.5) .* rel .* step)
end
function knots_random(n)
    return sort!(rand(RNG, n) .* 10.0)
end
function knots_cluster_then_sparse(n)
    # Half the knots packed near 0..1, half spread over 1..1000
    n1 = n ÷ 2
    n2 = n - n1
    return sort!(vcat(rand(RNG, n1), 1.0 .+ rand(RNG, n2) .* 999.0))
end

const KNOT_SPACINGS = (
    :uniform => knots_uniform,
    :log => knots_log,
    :jittered => knots_jittered,
    :random => knots_random,
    :two_scale => knots_cluster_then_sparse,
)

# ---------------------------------------------------------------------------
# Query-generation helpers
# ---------------------------------------------------------------------------

function queries_uniform(t::Vector, m::Integer)
    lo, hi = first(t), last(t)
    return sort!(lo .+ (hi - lo) .* rand(RNG, m))
end

function queries_dense_burst(t::Vector, m::Integer)
    # All queries inside a single tiny window in the middle of t
    n = length(t)
    i = max(1, n ÷ 2)
    lo, hi = t[i], t[min(i + 1, n)]
    return sort!(lo .+ (hi - lo) .* rand(RNG, m))
end

function queries_clustered_near_start(t::Vector, m::Integer)
    # 90% of queries in t[1]..t[max(2, n÷20)], 10% spread over the rest
    n = length(t)
    cutoff = max(2, n ÷ 20)
    lo1, hi1 = t[1], t[cutoff]
    lo2, hi2 = t[cutoff], t[end]
    n1 = max(1, (9 * m) ÷ 10)
    n2 = m - n1
    qs = vcat(
        lo1 .+ (hi1 - lo1) .* rand(RNG, n1),
        lo2 .+ (hi2 - lo2) .* rand(RNG, n2)
    )
    return sort!(qs)
end

function queries_unsorted(t::Vector, m::Integer)
    lo, hi = first(t), last(t)
    return lo .+ (hi - lo) .* rand(RNG, m)
end

const QUERY_PATTERNS = (
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
# Single-batch benchmark
# ---------------------------------------------------------------------------

"Returns minimum-time-per-batch (ns) for the given strategy on `(v, q)`."
function bench_batch(strategy::SearchStrategy, v::Vector, q::Vector)
    out = Vector{Int}(undef, length(q))
    b = @benchmark searchsortedlast!($out, $v, $q; strategy = $strategy) samples = 30 evals = 1
    return minimum(b).time   # ns
end

# Reference: Base.searchsortedlast applied per element
function bench_base(v::Vector, q::Vector)
    out = Vector{Int}(undef, length(q))
    b = @benchmark begin
        @inbounds for k in eachindex($q)
            $out[k] = searchsortedlast($v, $q[k])
        end
    end samples = 30 evals = 1
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

function run_sweep(; ns, ms, spacings, query_patterns, strategies)
    println("\n## Benchmark sweep\n")
    println(
        "| spacing | query pattern | n | m | ",
        join((s for (s, _) in strategies), " | "),
        " | base | best | best/auto |"
    )
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
                    # Determine best (excluding "Auto" itself)
                    best_name, best_t = "", Inf
                    for (name, t_) in results
                        name == "Auto" && continue
                        name == "base" && continue
                        if t_ < best_t
                            best_t = t_
                            best_name = name
                        end
                    end
                    auto_t = results["Auto"]
                    rel = auto_t / best_t
                    if rel < 0.95
                        auto_wins += 1   # shouldn't really happen unless Auto picks correctly
                    elseif rel > 1.2
                        auto_losses += 1
                    else
                        auto_within_20pct += 1
                    end
                    rows += 1

                    cols = String[
                        string(sp_name), string(qp_name), string(n), string(m),
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
        "$auto_wins effectively-faster-than-best (shouldn't happen)."
    )
    return nothing
end

# Fast sweep — small enough to run interactively
function fast_sweep()
    return run_sweep(
        ns = (64, 1024, 65_536),
        ms = (1, 10, 256, 4096),
        spacings = KNOT_SPACINGS,
        query_patterns = QUERY_PATTERNS,
        strategies = STRATEGIES,
    )
end

# Full sweep — slower
function full_sweep()
    return run_sweep(
        ns = (16, 64, 256, 1024, 4096, 65_536, 1_000_000),
        ms = (1, 10, 100, 1024, 4096),
        spacings = KNOT_SPACINGS,
        query_patterns = QUERY_PATTERNS,
        strategies = STRATEGIES,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = get(ENV, "MODE", "fast")
    if mode == "full"
        full_sweep()
    else
        fast_sweep()
    end
end

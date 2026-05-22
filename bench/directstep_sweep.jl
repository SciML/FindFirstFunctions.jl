using FindFirstFunctions, BenchmarkTools, StableRNGs, Printf

const F = FindFirstFunctions

# Per-query latency in nanoseconds. Uses BenchmarkTools' minimum sample over
# a fixed budget so jitter from one slow sample (GC, page fault) doesn't
# pollute the result.
function bench_query(strat, v, x)
    b = @benchmark searchsortedlast($strat, $v, $x) samples = 200 evals = 200
    return minimum(b.times)   # ns
end

function bench_query_hinted(strat, v, x, hint)
    b = @benchmark searchsortedlast($strat, $v, $x, $hint) samples = 200 evals = 200
    return minimum(b.times)   # ns
end

# Test queries: a random scatter across the full range, plus near-edge cases.
# We pick 8 queries and report the average of their per-query latencies, so
# the result reflects a mix of query positions rather than just the middle.
function bench_strategy_range(strat, r, queries)
    total = 0.0
    for x in queries
        total += bench_query(strat, r, x)
    end
    return total / length(queries)
end

function bench_strategy_hinted(strat, r, queries, hint_fn)
    total = 0.0
    for x in queries
        total += bench_query_hinted(strat, r, x, hint_fn(r, x))
    end
    return total / length(queries)
end

function make_queries(::Type{T}, r, seed) where {T}
    rng = StableRNG(seed)
    lo = Float64(first(r))
    hi = Float64(last(r))
    span = hi - lo
    raw = lo .+ rand(rng, 8) .* span
    return convert(Vector{T}, raw)
end

function format_row(label, t, base)
    speedup = base / t
    return @sprintf("%-44s %8.2f ns/q  %6.2fx", label, t, speedup)
end

function run_sweep()
    ns = (100, 1_000, 10_000, 100_000, 1_000_000)
    eltypes = (Float64, Float32)

    println("DirectStep sweep — per-query latency (lower is better).")
    println("Reported value is the average per-query time over 8 random queries")
    println("across the full range; each query is measured as the minimum of 200")
    println("samples × 200 evals via BenchmarkTools.")
    println()

    rows = Tuple{Type, Int, String, Float64}[]

    for T in eltypes
        for n in ns
            r = range(T(0), T(n); length = n)
            queries = make_queries(T, r, 2026)

            uniform_t = bench_strategy_range(UniformStep(), r, queries)
            ds = DirectStep(r)
            directstep_t = bench_strategy_range(ds, r, queries)

            # Bracket Gallop, hint near hit (compute the true answer and pass
            # it as hint, so the gallop costs ~0).
            good_hint = (r, x) -> max(1, searchsortedlast(r, x))
            bg_good_t = bench_strategy_hinted(
                BracketGallop(), r, queries, good_hint
            )
            # Bracket Gallop, stale hint = 1 (forces galloping from leftmost).
            stale_hint = (r, x) -> 1
            bg_stale_t = bench_strategy_hinted(
                BracketGallop(), r, queries, stale_hint
            )

            println("--- $T  n=$n ---")
            base = uniform_t
            println(format_row("UniformStep         (Range)", uniform_t, base))
            println(format_row("DirectStep          (Range)", directstep_t, base))
            println(format_row("BracketGallop+good_hint (Range)", bg_good_t, base))
            println(format_row("BracketGallop+stale_hint (Range)", bg_stale_t, base))
            println()
            push!(rows, (T, n, "UniformStep", uniform_t))
            push!(rows, (T, n, "DirectStep", directstep_t))
            push!(rows, (T, n, "BracketGallop+good_hint", bg_good_t))
            push!(rows, (T, n, "BracketGallop+stale_hint", bg_stale_t))
        end
    end

    println("=== Vector path comparison (Float64, n=10_000) ===")
    let r = range(0.0, 10_000.0; length = 10_000),
            v = collect(r),
            queries = make_queries(Float64, r, 2026)
        bb_t = bench_strategy_range(BinaryBracket(), v, queries)
        ds = DirectStep(v, Val(:uniform))
        ds_t = bench_strategy_range(ds, v, queries)
        base = bb_t
        println(format_row("BinaryBracket     (Vector{Float64})", bb_t, base))
        println(format_row("DirectStep        (Vector{Float64})", ds_t, base))
    end
    println()

    return rows
end

run_sweep()

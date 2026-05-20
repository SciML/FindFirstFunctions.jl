using FindFirstFunctions, StableRNGs, BenchmarkTools, Statistics, Printf

const F = FindFirstFunctions

# --------------------------------------------------------------------------
# Strategy registry — every strategy that competes in the sorted-batched
# regime. BinaryBracket is excluded from the per-cell winner pool because it
# never wins under any reasonable workload (no hint = full binary search
# per query); it's only useful as a fallback. Auto's actual choices are
# LinearScan / SIMDLinearScan / ExpFromLeft / InterpolationSearch.
# --------------------------------------------------------------------------
const STRATS = [
    ("LinearScan", F.LinearScan()),
    ("SIMDLinearScan", F.SIMDLinearScan()),
    ("BracketGallop", F.BracketGallop()),
    ("ExpFromLeft", F.ExpFromLeft()),
    ("InterpolationSearch", F.InterpolationSearch()),
]

# --------------------------------------------------------------------------
# v patterns (sorted vectors of length n)
# --------------------------------------------------------------------------
function make_v(::Val{:uniform}, ::Type{T}, n, seed) where {T <: AbstractFloat}
    return collect(T, range(zero(T), T(n); length = n))
end
function make_v(::Val{:uniform}, ::Type{T}, n, seed) where {T <: Integer}
    return collect(T, T(1):T(n))
end
function make_v(::Val{:jittered}, ::Type{T}, n, seed) where {T <: AbstractFloat}
    rng = StableRNG(seed)
    base = collect(range(0.0, Float64(n); length = n))
    return convert(Vector{T}, sort!(base .+ 0.1 .* (rand(rng, n) .- 0.5)))
end
function make_v(::Val{:jittered}, ::Type{T}, n, seed) where {T <: Integer}
    rng = StableRNG(seed)
    raw = sort!(unique!(rand(rng, T(1):T(2n), n)))
    return convert(Vector{T}, raw)
end
function make_v(::Val{:logspaced}, ::Type{T}, n, seed) where {T <: AbstractFloat}
    return collect(T, exp.(range(0.0, log(1.0e6); length = n)))
end
function make_v(::Val{:logspaced}, ::Type{T}, n, seed) where {T <: Integer}
    raw = sort!(unique!(round.(T, exp.(range(0.0, log(Float64(10n)); length = n)))))
    return convert(Vector{T}, raw)
end
function make_v(::Val{:twoscale}, ::Type{T}, n, seed) where {T <: AbstractFloat}
    h = n ÷ 2
    return convert(
        Vector{T},
        sort!(vcat(range(0.0, 0.1n; length = h), range(0.1n, Float64(n); length = n - h)))
    )
end
function make_v(::Val{:twoscale}, ::Type{T}, n, seed) where {T <: Integer}
    h = n ÷ 2
    a = round.(T, range(1.0, 0.1n; length = h))
    b = round.(T, range(0.1n + 1, Float64(n); length = n - h))
    return convert(Vector{T}, sort!(vcat(a, b)))
end
function make_v(::Val{:random_sorted}, ::Type{T}, n, seed) where {T <: AbstractFloat}
    return convert(Vector{T}, sort!(rand(StableRNG(seed), n) .* n))
end
function make_v(::Val{:random_sorted}, ::Type{T}, n, seed) where {T <: Integer}
    return convert(Vector{T}, sort!(rand(StableRNG(seed), T(1):T(10n), n)))
end

# --------------------------------------------------------------------------
# query patterns
# --------------------------------------------------------------------------
function _to_eltype(v, xs)
    T = eltype(v)
    return T <: Integer ? convert(Vector{T}, round.(T, xs)) : convert(Vector{T}, xs)
end
function make_q(::Val{:dense}, v, m, seed)
    raw = collect(range(Float64(first(v)), Float64(last(v)); length = m))
    return _to_eltype(v, raw)
end
function make_q(::Val{:sparse}, v, m, seed)
    rng = StableRNG(seed)
    span = Float64(last(v)) - Float64(first(v))
    raw = sort!(Float64(first(v)) .+ rand(rng, m) .* span)
    return _to_eltype(v, raw)
end
function make_q(::Val{:clustered}, v, m, seed)
    rng = StableRNG(seed)
    j = max(1, length(v) ÷ 4)
    lo = Float64(v[j])
    hi = Float64(v[min(j + 1, length(v))])
    span = hi - lo
    raw = sort!(lo .+ rand(rng, m) .* max(span, 1.0))
    return _to_eltype(v, raw)
end
function make_q(::Val{:sorted_random}, v, m, seed)
    rng = StableRNG(seed)
    span = Float64(last(v)) - Float64(first(v))
    raw = sort!(Float64(first(v)) .+ rand(rng, m) .* span)
    return _to_eltype(v, raw)
end

# --------------------------------------------------------------------------
# Bench a single (v, queries, strategy) cell. Returns time in nanoseconds.
# Uses a fixed-repeat loop to avoid BenchmarkTools per-call overhead, which
# dominates fast strategies on small m.
# --------------------------------------------------------------------------
function bench_one(v, queries, strat, out, reps::Int = 5)
    # Warm up
    F.searchsortedlast!(out, v, queries; strategy = strat)
    # Measure
    best = typemax(Float64)
    for _ in 1:reps
        t = @elapsed F.searchsortedlast!(out, v, queries; strategy = strat)
        best = min(best, t)
    end
    return best * 1.0e9 / length(queries)   # ns per query
end

# --------------------------------------------------------------------------
# Full sweep
# --------------------------------------------------------------------------
function run_sweep(;
        v_kinds = (:uniform, :jittered, :logspaced, :twoscale, :random_sorted),
        q_kinds = (:dense, :sparse, :clustered, :sorted_random),
        ns = (256, 1024, 4096, 16_384, 65_536),
        ms = (4, 16, 64, 256, 1024, 4096),
        eltypes = (Int64, Float64),
        seed = 2026,
    )
    rows = []
    cell_idx = 0
    n_cells = length(v_kinds) * length(q_kinds) * length(ns) * length(ms) * length(eltypes)

    for T in eltypes, v_kind in v_kinds, q_kind in q_kinds, n in ns, m in ms
        m > n && continue
        cell_idx += 1
        v = make_v(Val(v_kind), T, n, seed)
        q = make_q(Val(q_kind), v, m, seed + 1)
        out = Vector{Int}(undef, m)

        # Build SearchProperties for the cached-Auto comparison
        props = F.SearchProperties(v)

        times = Dict{String, Float64}()
        for (name, strat) in STRATS
            t = bench_one(v, q, strat, out)
            times[name] = t
        end
        # Auto (un-cached) and Auto (cached)
        times["Auto"] = bench_one(v, q, F.Auto(), out)
        times["Auto+props"] = bench_one(v, q, F.Auto(props), out)

        push!(
            rows, (
                eltype = string(T),
                v_kind = string(v_kind),
                q_kind = string(q_kind),
                n = n,
                m = m,
                times = times,
            )
        )

        if cell_idx % 25 == 0
            best_explicit = minimum(times[s] for s in first.(STRATS))
            @printf(
                "  [%4d/%4d] %s/%s/%s n=%d m=%d  best=%.0f ns/q  Auto=%.0f  Auto+p=%.0f\n",
                cell_idx, n_cells, T, v_kind, q_kind, n, m,
                best_explicit, times["Auto"], times["Auto+props"]
            )
        end
    end
    return rows
end

# --------------------------------------------------------------------------
# Analyze: per-cell winner, Auto slack vs best
# --------------------------------------------------------------------------
function analyze(rows)
    strat_names = first.(STRATS)
    summary = Dict{String, Int}()
    auto_slacks = Float64[]
    auto_cached_slacks = Float64[]

    for r in rows
        # Find the per-cell winner among the explicit strategies.
        per_cell = [(s, r.times[s]) for s in strat_names]
        best_t = minimum(p[2] for p in per_cell)
        best_name = first(per_cell[argmin([p[2] for p in per_cell])])
        summary[best_name] = get(summary, best_name, 0) + 1
        push!(auto_slacks, r.times["Auto"] / best_t)
        push!(auto_cached_slacks, r.times["Auto+props"] / best_t)
    end

    println()
    println("Per-cell winners (across $(length(rows)) cells):")
    for name in strat_names
        n = get(summary, name, 0)
        @printf("  %-22s %5d cells (%5.1f%%)\n", name, n, 100 * n / length(rows))
    end

    println()
    @printf("Auto slack (Auto-time / per-cell-best-time):\n")
    @printf(
        "  median %.2fx, mean %.2fx, p90 %.2fx, p95 %.2fx, max %.2fx\n",
        median(auto_slacks), mean(auto_slacks),
        quantile(auto_slacks, 0.9), quantile(auto_slacks, 0.95),
        maximum(auto_slacks)
    )
    @printf("Auto(props) slack:\n")
    @printf(
        "  median %.2fx, mean %.2fx, p90 %.2fx, p95 %.2fx, max %.2fx\n",
        median(auto_cached_slacks), mean(auto_cached_slacks),
        quantile(auto_cached_slacks, 0.9), quantile(auto_cached_slacks, 0.95),
        maximum(auto_cached_slacks)
    )

    return summary, auto_slacks, auto_cached_slacks
end

function print_worst_cells(rows, k = 20)
    strat_names = first.(STRATS)
    println()
    println("Worst Auto-slack cells (current Auto picks strategy that's much slower than optimal):")
    @printf(
        "  %-7s %-15s %-15s %6s %6s   %-20s slack(Auto) slack(Auto+p)\n",
        "eltype", "v_kind", "q_kind", "n", "m", "best (time)"
    )
    scored = [
        (r, r.times["Auto"] / minimum(r.times[s] for s in strat_names))
            for r in rows
    ]
    sort!(scored; by = x -> -x[2])
    for (r, slack) in scored[1:min(k, length(scored))]
        best_t = minimum(r.times[s] for s in strat_names)
        best_name = strat_names[argmin([r.times[s] for s in strat_names])]
        slack_cached = r.times["Auto+props"] / best_t
        @printf(
            "  %-7s %-15s %-15s %6d %6d   %-15s %.0fns  %5.2fx     %5.2fx\n",
            r.eltype, r.v_kind, r.q_kind, r.n, r.m, best_name, best_t,
            slack, slack_cached
        )
    end
    return
end

println("FindFirstFunctions Auto algorithm benchmark sweep")
println("="^70)
println("Strategies:")
for (name, _) in STRATS
    println("  ", name)
end
println("Plus: Auto(), Auto(SearchProperties(v))")
println()
println("Starting sweep...")
println()

@time rows = run_sweep()

println()
println("Sweep complete.")
println()

analyze(rows)
print_worst_cells(rows, 30)

open(joinpath(@__DIR__, "results.csv"), "w") do io
    header = ["eltype", "v_kind", "q_kind", "n", "m"]
    append!(header, first.(STRATS))
    push!(header, "Auto", "Auto+props")
    println(io, join(header, ","))
    for r in rows
        cols = String[r.eltype, r.v_kind, r.q_kind, string(r.n), string(r.m)]
        for s in first.(STRATS)
            push!(cols, string(r.times[s]))
        end
        push!(cols, string(r.times["Auto"]))
        push!(cols, string(r.times["Auto+props"]))
        println(io, join(cols, ","))
    end
end
println("\nRaw data: bench/results.csv")

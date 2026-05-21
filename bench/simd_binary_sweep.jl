# Bench sweep: `SIMDBinarySearch` vs `BinaryBracket` (`Base.searchsortedlast`)
# for single-query workloads across n × eltype × cache state.
#
# Strategy is opt-in only and ignores any hint. To make the comparison fair
# we drive each strategy with the same per-query loop — no batched API, no
# hint chaining — and measure ns per query.
#
# Two cache regimes:
#   - hot:   v stays resident; consecutive queries see warm cache lines.
#   - cold:  cycle through a working set of independent v vectors whose
#            combined footprint is larger than LLC, so each v's first probe
#            sees a cold cache line. Larger n covers more of the working set
#            per single query and the steady-state cache pressure is what we
#            measure.

using FindFirstFunctions, StableRNGs, BenchmarkTools, Printf, Statistics

const F = FindFirstFunctions

# Strategies under test.
const STRATS = [
    ("SIMDBinary", F.SIMDBinarySearch()),
    ("BinaryBracket", F.BinaryBracket()),
]

# ---- query-loop kernels (no batched API, no hint) -------------------------

@inline function loop_last!(strat, v, qs, out)
    @inbounds for i in eachindex(qs)
        out[i] = searchsortedlast(strat, v, qs[i])
    end
    return out
end

@inline function loop_first!(strat, v, qs, out)
    @inbounds for i in eachindex(qs)
        out[i] = searchsortedfirst(strat, v, qs[i])
    end
    return out
end

# Cold-cache driver: cycle through a working set of independent v vectors
# whose combined bytes exceed LLC (default 256 MiB). Each query consumes one
# v from the working set; we sweep through often enough that the v we're
# about to use was last touched many MiB ago.
const COLD_WORKING_SET_BYTES = 256 * 1024 * 1024

@inline function loop_last_cold!(strat, vs, qs, out)
    nv = length(vs)
    @inbounds for i in eachindex(qs)
        v = vs[mod1(i, nv)]
        out[i] = searchsortedlast(strat, v, qs[i])
    end
    return out
end

# ---- timing helpers --------------------------------------------------------

function time_hot(strat, v, qs, out, reps = 7)
    loop_last!(strat, v, qs, out)   # warmup
    best = typemax(Float64)
    for _ in 1:reps
        t = @elapsed loop_last!(strat, v, qs, out)
        best = min(best, t)
    end
    return best * 1.0e9 / length(qs)
end

function time_cold(strat, vs, qs, out, reps = 5)
    # Cold-cache: each query reads from a different v in a working-set-larger-
    # than-LLC pool, so probes that hit "v's data" almost always miss cache.
    loop_last_cold!(strat, vs, qs, out)   # warmup
    best = typemax(Float64)
    for _ in 1:reps
        t = @elapsed loop_last_cold!(strat, vs, qs, out)
        best = min(best, t)
    end
    return best * 1.0e9 / length(qs)
end

# ---- workload generation ---------------------------------------------------

function build_v(::Type{Float64}, n, seed)
    return collect(range(1.0, Float64(n); length = n))
end
function build_v(::Type{Int64}, n, seed)
    return collect(Int64(1):Int64(n))
end

function build_queries(::Type{Float64}, v, m, seed)
    rng = StableRNG(seed)
    return rand(rng, m) .* (last(v) - first(v)) .+ first(v)
end
function build_queries(::Type{Int64}, v, m, seed)
    rng = StableRNG(seed)
    return rand(rng, Int64(first(v)):Int64(last(v)), m)
end

# ---- sweep -----------------------------------------------------------------

function build_cold_working_set(::Type{T}, n, seed) where {T}
    # Build enough independent vectors so the total bytes exceed LLC.
    bytes_per_v = n * sizeof(T)
    nv = max(2, cld(COLD_WORKING_SET_BYTES, bytes_per_v))
    rng = StableRNG(seed)
    vs = Vector{Vector{T}}(undef, nv)
    for i in 1:nv
        # Each v is the same shape (1..n) but offset so queries hit
        # well-defined positions regardless of which v is picked.
        vs[i] = build_v(T, n, seed + i)
    end
    return vs
end

function build_cold_queries(::Type{T}, vs, m, seed) where {T}
    rng = StableRNG(seed)
    # Choose a query uniformly across the common range of each v.
    return [
        T == Float64 ?
            T(rand(rng) * (length(vs[1]) - 1) + 1) :
            T(rand(rng, 1:length(vs[1])))
            for _ in 1:m
    ]
end

function run_sweep()
    ns = (256, 1024, 4096, 16_384, 65_536, 262_144, 1_048_576)
    eltypes = (Float64, Int64)
    # Number of queries per timing rep — large enough that per-query timing
    # noise is small, small enough that the whole sweep finishes in minutes.
    m_hot = 65_536
    m_cold = 4096

    println("SIMDBinarySearch vs BinaryBracket — single-query sweep")
    println("="^78)
    println(
        "Hot cache: $(m_hot) queries / rep; cold cache: $(m_cold) queries / rep"
    )
    @printf(
        "Cold cycles through a working set ≥ %d MiB so each v is cold.\n",
        COLD_WORKING_SET_BYTES ÷ (1024 * 1024)
    )
    println()

    rows = []

    for T in eltypes
        println("=== eltype = $T ===")
        @printf(
            "%9s | %28s | %28s\n",
            "n",
            "hot   (ns/q, SIMD vs Base)",
            "cold  (ns/q, SIMD vs Base)"
        )
        println("-"^78)
        for n in ns
            v = build_v(T, n, 1)
            qs_hot = build_queries(T, v, m_hot, 2)
            out_hot = Vector{Int}(undef, m_hot)

            # Cold: cycle through independent v's.
            vs_cold = build_cold_working_set(T, n, 1000)
            qs_cold = build_cold_queries(T, vs_cold, m_cold, 3)
            out_cold = Vector{Int}(undef, m_cold)

            simd_hot = time_hot(F.SIMDBinarySearch(), v, qs_hot, out_hot)
            base_hot = time_hot(F.BinaryBracket(), v, qs_hot, out_hot)
            simd_cold = time_cold(F.SIMDBinarySearch(), vs_cold, qs_cold, out_cold)
            base_cold = time_cold(F.BinaryBracket(), vs_cold, qs_cold, out_cold)

            push!(
                rows,
                (T, n, simd_hot, base_hot, simd_cold, base_cold)
            )
            @printf(
                "%9d | SIMD=%9.1f Base=%9.1f | SIMD=%9.1f Base=%9.1f\n",
                n, simd_hot, base_hot, simd_cold, base_cold
            )
        end
        println()
    end

    println()
    println("Winner table (lower ns/q wins; tied = within 5%):")
    println("="^78)
    @printf(
        "%-9s %-9s | %-12s %-12s | %-12s %-12s\n",
        "eltype", "n", "hot winner", "ratio S/B", "cold winner", "ratio S/B"
    )
    println("-"^78)
    for (T, n, sh, bh, sc, bc) in rows
        rh = sh / bh
        rc = sc / bc
        wh = rh < 0.95 ? "SIMD" : (rh > 1.05 ? "Base" : "tie")
        wc = rc < 0.95 ? "SIMD" : (rc > 1.05 ? "Base" : "tie")
        @printf(
            "%-9s %-9d | %-12s %-12.2f | %-12s %-12.2f\n",
            T, n, wh, rh, wc, rc
        )
    end
    return rows
end

if !isinteractive() && abspath(PROGRAM_FILE) == @__FILE__
    rows = @time run_sweep()
end

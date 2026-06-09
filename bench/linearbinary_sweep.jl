# LinearBinarySearch{MAX} parameter sweep.
#
# Compares LinearBinarySearch{MAX} for MAX ∈ {4, 8, 16, 32} against
# BracketGallop, ExpFromLeft, LinearScan, SIMDLinearScan, and the plain
# `Base.searchsortedlast` (no strategy) across a range of `n` and
# hint-to-answer gaps.
#
# The hypothesis under test: for small constant gaps (≤ MAX), the linear
# walk wins because it skips the exponential-doubling overhead in
# ExpFromLeft / BracketGallop. At larger gaps the binary fallback should
# still keep it within a small factor of the gallop strategies.

using FindFirstFunctions, BenchmarkTools, StableRNGs, Printf, Statistics

const F = FindFirstFunctions

# Single batched sweep: from a starting hint, perform `m` queries each
# `gap` apart. Returns ns/query.
function bench_strategy(strat, v::Vector{Float64}, gap::Int, m::Int)
    n = length(v)
    # Build a sequence of queries placed `gap` indices apart starting at
    # an offset that keeps everything inside [1, n].
    start = max(1, (n - gap * (m + 1)) ÷ 2)
    queries = [Float64(v[start + i * gap]) for i in 0:(m - 1)]
    # Warm up.
    out = Vector{Int}(undef, m)
    F.searchsortedlast!(out, v, queries; strategy = strat)
    b = @benchmark F.searchsortedlast!($out, $v, $queries; strategy = $strat) samples = 50 evals = 1
    return minimum(b.times) / m   # ns/query
end

function bench_base(v::Vector{Float64}, gap::Int, m::Int)
    n = length(v)
    start = max(1, (n - gap * (m + 1)) ÷ 2)
    queries = [Float64(v[start + i * gap]) for i in 0:(m - 1)]
    out = Vector{Int}(undef, m)
    for i in 1:m
        @inbounds out[i] = searchsortedlast(v, queries[i])
    end
    b = @benchmark begin
        for i in 1:length($queries)
            @inbounds $out[i] = searchsortedlast($v, $queries[i])
        end
    end samples = 50 evals = 1
    return minimum(b.times) / m
end

const NS = (100, 1_000, 10_000, 100_000, 1_000_000)
const GAPS = (1, 2, 4, 8, 16, 32, 64, 128)
const MAXS = (4, 8, 16, 32)

const STRATS_FIXED = [
    ("LinearScan", F.LinearScan()),
    ("BracketGallop", F.BracketGallop()),
    ("ExpFromLeft", F.ExpFromLeft()),
]

function main()
    println("LinearBinarySearch{MAX} sweep — ns/query (lower is better)")
    println("="^96)

    # Number of queries per sweep — m=64 is enough that per-call kwarg
    # trampoline overhead is amortized out.
    m = 64

    for n in NS
        v = collect(range(0.0, 1.0e6; length = n))
        @printf "\n n = %d\n" n
        # Header
        @printf "  %-6s" "gap"
        for (name, _) in STRATS_FIXED
            @printf " | %-12s" name
        end
        for MAX in MAXS
            @printf " | LBS{%-3d}    " MAX
        end
        @printf " | %-12s\n" "Base"
        println("  " * "-"^(6 + (length(STRATS_FIXED) + length(MAXS) + 1) * 15))

        for gap in GAPS
            # Skip combinations where m queries × gap overruns the array.
            (m + 1) * gap > n - 2 && continue
            @printf "  %-6d" gap
            for (_, strat) in STRATS_FIXED
                t = bench_strategy(strat, v, gap, m)
                @printf " | %10.2f  " t
            end
            for MAX in MAXS
                strat = F.LinearBinarySearch(MAX)
                t = bench_strategy(strat, v, gap, m)
                @printf " | %10.2f  " t
            end
            t = bench_base(v, gap, m)
            @printf " | %10.2f\n" t
        end
    end

    println("\n\n" * "="^96)
    println("Per-query single-call sweep (one query, one hint — no batching)")
    println("="^96)
    println("Mimics the per-call API the way `Auto` per-query dispatch sees it.\n")

    for n in (1_000, 100_000)
        v = collect(range(0.0, 1.0e6; length = n))
        @printf " n = %d\n" n
        @printf "  %-6s" "gap"
        for MAX in MAXS
            @printf " | LBS{%-3d}    " MAX
        end
        @printf " | %-12s | %-12s | %-12s\n" "LinearScan" "BracketGallop" "ExpFromLeft"
        println("  " * "-"^(6 + (length(MAXS) + 3) * 15))
        for gap in GAPS
            (gap + 2) > n - 2 && continue
            hint = max(1, n ÷ 2)
            answer = hint + gap
            answer > n && continue
            x = v[answer]
            @printf "  %-6d" gap
            for MAX in MAXS
                strat = F.LinearBinarySearch(MAX)
                b = @benchmark searchsortedlast($strat, $v, $x, $hint) samples = 200 evals = 50
                @printf " | %10.2f  " minimum(b.times)
            end
            for strat in (F.LinearScan(), F.BracketGallop(), F.ExpFromLeft())
                b = @benchmark searchsortedlast($strat, $v, $x, $hint) samples = 200 evals = 50
                @printf " | %10.2f  " minimum(b.times)
            end
            println()
        end
        println()
    end
    return nothing
end

main()

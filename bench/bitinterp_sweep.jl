using FindFirstFunctions, StableRNGs, BenchmarkTools, Statistics, Printf

const F = FindFirstFunctions

# Strategies under test. BitInterp is the one we're vetting; the others are
# the alternatives `Auto` might pick or that a user might pin.
const STRATS = [
    ("BitInterp", F.BitInterpolationSearch()),
    ("Interp", F.InterpolationSearch()),
    ("Bracket", F.BracketGallop()),
    ("Exp", F.ExpFromLeft()),
    ("SIMD", F.SIMDLinearScan()),
    ("Auto", F.Auto()),
]

# Data shapes covering the regimes BitInterp could conceivably win.
function build_v(::Val{:uniform}, n, seed)
    return collect(range(1.0, Float64(n); length = n))
end
function build_v(::Val{:logspaced}, n, seed)
    return collect(exp.(range(0.0, log(1.0e6); length = n)))
end
function build_v(::Val{:logspaced_wide}, n, seed)
    # 10⁻³ to 10¹⁵ — ~18 decades, like a particle-physics interpolation table
    return collect(exp.(range(log(1.0e-3), log(1.0e15); length = n)))
end
function build_v(::Val{:geometric_dense}, n, seed)
    # Geometric with ratio chosen so the series spans 10⁶ — keeps Float64
    # range usable up to n ≈ 10⁷ while keeping the spacing tight.
    r = (1.0e6)^(1.0 / max(n - 1, 1))
    return collect(r .^ (0:(n - 1)))
end
function build_v(::Val{:geometric_sparse}, n, seed)
    # Geometric spanning 10¹² with sparser spacing.
    r = (1.0e12)^(1.0 / max(n - 1, 1))
    return collect(r .^ (0:(n - 1)))
end
function build_v(::Val{:power2}, n, seed)
    return collect(Float64(i)^2 for i in 1:n)
end
function build_v(::Val{:sqrt}, n, seed)
    return collect(sqrt(Float64(i)) for i in 1:n)
end
function build_v(::Val{:two_decade}, n, seed)
    # 80% of values in [1, 2], 20% in [2, 1e6] — extreme density-then-sparse
    h = (8n) ÷ 10
    a = collect(range(1.0, 2.0; length = h))
    b = collect(exp.(range(log(2.0), log(1.0e6); length = n - h)))
    return sort!(vcat(a[1:(end - 1)], b))
end
function build_v(::Val{:jittered_log}, n, seed)
    base = collect(exp.(range(0.0, log(1.0e6); length = n)))
    rng = StableRNG(seed)
    return sort!(base .* (1.0 .+ 0.01 .* (rand(rng, n) .- 0.5)))
end

function build_q(v, m, kind::Symbol, seed)
    rng = StableRNG(seed)
    if kind == :linear_uniform
        # m queries uniformly random in v's full LINEAR range
        return sort!(first(v) .+ rand(rng, m) .* (last(v) - first(v)))
    elseif kind == :log_uniform
        # m queries uniformly random in v's full LOG range — matches the
        # distribution of log-spaced v itself
        first(v) > 0 || error("log_uniform requires positive v")
        return sort!(
            exp.(log(first(v)) .+ rand(rng, m) .* (log(last(v)) - log(first(v))))
        )
    elseif kind == :dense_grid
        # Evenly-spaced linear grid
        return collect(range(first(v), last(v); length = m))
    elseif kind == :log_grid
        first(v) > 0 || error("log_grid requires positive v")
        return collect(exp.(range(log(first(v)), log(last(v)); length = m)))
    else
        error("unknown q kind: $kind")
    end
end

function bench_cell(v, q, strat, out, reps = 5)
    F.searchsortedlast!(out, v, q; strategy = strat)
    best = typemax(Float64)
    for _ in 1:reps
        t = @elapsed F.searchsortedlast!(out, v, q; strategy = strat)
        best = min(best, t)
    end
    return best * 1.0e9 / length(q)
end

function correctness_check(v, q, strat)
    out = Vector{Int}(undef, length(q))
    expected = searchsortedlast.(Ref(v), q)
    F.searchsortedlast!(out, v, q; strategy = strat)
    return out == expected
end

println("BitInterpolationSearch comprehensive sweep")
println("="^70)
println("Testing where BitInterp might win across spacing × density × n × m")
println()

# Multiple seeds for noise reduction
function run_sweep()
    v_kinds = (
        :uniform, :logspaced, :logspaced_wide,
        :geometric_dense, :geometric_sparse,
        :power2, :sqrt, :two_decade, :jittered_log,
    )
    q_kinds = (:linear_uniform, :log_uniform, :dense_grid, :log_grid)
    ns = (1024, 4096, 16_384, 65_536, 262_144, 1_048_576)
    ms = (4, 16, 64, 256, 1024, 4096, 16_384)

    rows = []
    bit_wins = 0
    bit_within10 = 0  # within 10% of best
    bit_within20 = 0  # within 20% of best
    total = 0

    for v_kind in v_kinds, q_kind in q_kinds, n in ns, m in ms
        m > n && continue
        v = build_v(Val(v_kind), n, 2026)
        # Some q_kinds require positive v
        if (q_kind == :log_uniform || q_kind == :log_grid) && first(v) <= 0
            continue
        end
        q = build_q(v, m, q_kind, 2027)
        out = Vector{Int}(undef, m)

        # Correctness first — bail loudly if mismatch.
        correctness_check(v, q, F.BitInterpolationSearch()) ||
            error("BitInterp correctness fail on $v_kind/$q_kind n=$n m=$m")

        times = Dict{String, Float64}()
        for (name, strat) in STRATS
            times[name] = bench_cell(v, q, strat, out)
        end
        push!(rows, (v_kind, q_kind, n, m, times))

        # Score
        explicit = [(n, t) for (n, t) in pairs(times) if n != "Auto"]
        best_t = minimum(t for (_, t) in explicit)
        bit_t = times["BitInterp"]
        if bit_t <= best_t
            bit_wins += 1
        end
        if bit_t <= 1.1 * best_t
            bit_within10 += 1
        end
        if bit_t <= 1.2 * best_t
            bit_within20 += 1
        end
        total += 1
    end

    println("Cells tested: $total")
    @printf(
        "BitInterp wins outright:   %d cells (%.1f%%)\n",
        bit_wins, 100 * bit_wins / total
    )
    @printf(
        "BitInterp within 10%% of best: %d cells (%.1f%%)\n",
        bit_within10, 100 * bit_within10 / total
    )
    @printf(
        "BitInterp within 20%% of best: %d cells (%.1f%%)\n",
        bit_within20, 100 * bit_within20 / total
    )
    println()

    # If BitInterp wins anywhere, show those cells.
    win_rows = [
        r for r in rows if begin
                explicit = [(n, t) for (n, t) in pairs(r[5]) if n != "Auto"]
                best_t = minimum(t for (_, t) in explicit)
                r[5]["BitInterp"] <= best_t
            end
    ]
    if !isempty(win_rows)
        println("Cells where BitInterp wins:")
        @printf(
            "  %-16s %-14s %8s %6s   %-10s vs second-best\n",
            "v_kind", "q_kind", "n", "m", "BitInterp"
        )
        for (v_kind, q_kind, n, m, times) in win_rows
            explicit = sort(
                [(name, t) for (name, t) in pairs(times) if name != "Auto"];
                by = x -> x[2]
            )
            second = explicit[2]
            @printf(
                "  %-16s %-14s %8d %6d   %5.1f ns/q  vs %s=%5.1f (%.2fx)\n",
                v_kind, q_kind, n, m, times["BitInterp"],
                second[1], second[2], second[2] / times["BitInterp"]
            )
        end
        println()
    end

    # Show the cells where BitInterp is closest to winning (top 10).
    closest = sort(
        rows; by = r -> begin
            explicit = [(n, t) for (n, t) in pairs(r[5]) if n != "Auto"]
            best_t = minimum(t for (_, t) in explicit)
            r[5]["BitInterp"] / best_t
        end
    )
    println("Closest 10 cells (BitInterp/best ratio):")
    @printf(
        "  %-16s %-14s %8s %6s   %-10s ratio winner\n",
        "v_kind", "q_kind", "n", "m", "BitInterp"
    )
    for (v_kind, q_kind, n, m, times) in closest[1:min(10, end)]
        explicit = [(name, t) for (name, t) in pairs(times) if name != "Auto"]
        best_t = minimum(t for (_, t) in explicit)
        winner = first(sort(explicit; by = x -> x[2]))
        @printf(
            "  %-16s %-14s %8d %6d   %5.1f ns/q  %.2fx  %s\n",
            v_kind, q_kind, n, m, times["BitInterp"],
            times["BitInterp"] / best_t, winner[1]
        )
    end

    return rows
end

@time run_sweep()

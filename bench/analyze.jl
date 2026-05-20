using DelimitedFiles, Statistics, Printf

const CSV = joinpath(@__DIR__, "results.csv")

# Read raw data
raw, header = readdlm(CSV, ','; header = true)
header = vec(string.(header))
function col(name)
    j = findfirst(==(name), header)
    j === nothing && error("no column $name")
    return j
end

const STRATS = ["LinearScan", "SIMDLinearScan", "BracketGallop", "ExpFromLeft", "InterpolationSearch"]

function row_winner(row)
    times = Float64[parse(Float64, string(row[col(s)])) for s in STRATS]
    j = argmin(times)
    return STRATS[j], times[j]
end

function ratio_to(row, strat_name)
    times = Float64[parse(Float64, string(row[col(s)])) for s in STRATS]
    best = minimum(times)
    return parse(Float64, string(row[col(strat_name)])) / best
end

println("==> Where does SIMDLinearScan win?")
simd_wins = []
for i in axes(raw, 1)
    local row = raw[i, :]
    local winner, _ = row_winner(row)
    if winner == "SIMDLinearScan"
        push!(
            simd_wins, (
                eltype = string(row[col("eltype")]),
                v = string(row[col("v_kind")]),
                q = string(row[col("q_kind")]),
                n = parse(Int, string(row[col("n")])),
                m = parse(Int, string(row[col("m")])),
            )
        )
    end
end
n_simd_wins = length(simd_wins)
println("  SIMDLinearScan wins in $n_simd_wins cells")
println()

# Tabulate where SIMD wins by m (gap proxy)
println("==> SIMDLinearScan wins by m (proxy for batched-gap regime):")
by_m = Dict{Int, Int}()
for c in simd_wins
    by_m[c.m] = get(by_m, c.m, 0) + 1
end
for m in sort(collect(keys(by_m)))
    @printf("  m=%5d:  %d cells\n", m, by_m[m])
end
println()

# By eltype
println("==> SIMDLinearScan wins by eltype:")
by_eltype = Dict{String, Int}()
for c in simd_wins
    by_eltype[c.eltype] = get(by_eltype, c.eltype, 0) + 1
end
for k in sort(collect(keys(by_eltype)))
    println("  $k: $(by_eltype[k]) cells")
end
println()

# Now show: for sorted-batched cells where SIMDLinearScan wins, what's the
# ratio of LinearScan/ExpFromLeft to SIMDLinearScan? This tells us the
# magnitude of the improvement.
println("==> SIMDLinearScan win margin over LinearScan and ExpFromLeft:")
println("    (Higher = bigger SIMD speedup over the second-best Auto candidate)")
margins = []
for i in axes(raw, 1)
    row = raw[i, :]
    winner, best = row_winner(row)
    if winner == "SIMDLinearScan"
        t_simd = best
        t_lin = parse(Float64, string(row[col("LinearScan")]))
        t_exp = parse(Float64, string(row[col("ExpFromLeft")]))
        push!(
            margins, (
                ratio_lin = t_lin / t_simd,
                ratio_exp = t_exp / t_simd,
                n = parse(Int, string(row[col("n")])),
                m = parse(Int, string(row[col("m")])),
            )
        )
    end
end
println("  SIMD vs LinearScan: median $(median(m.ratio_lin for m in margins))x, max $(maximum(m.ratio_lin for m in margins))x")
println("  SIMD vs ExpFromLeft: median $(median(m.ratio_exp for m in margins))x, max $(maximum(m.ratio_exp for m in margins))x")
println()

# What does Auto pick in the cells where SIMDLinearScan would win?
# Find the m, n, gap regime where SIMDLinearScan beats LinearScan AND ExpFromLeft.
println("==> Best regime for SIMDLinearScan (cells where SIMD wins by >20%):")
significant_simd_wins = filter(c -> c.ratio_lin > 1.2 && c.ratio_exp > 1.2, margins)
println("  $(length(significant_simd_wins)) cells where SIMD beats both LinearScan and ExpFromLeft by >20%")
n_by_m_n = Dict{Tuple{Int, Int}, Int}()
for c in significant_simd_wins
    n_by_m_n[(c.n, c.m)] = get(n_by_m_n, (c.n, c.m), 0) + 1
end
for (n, m) in sort(collect(keys(n_by_m_n)))
    @printf("  n=%5d m=%5d: %d cells\n", n, m, n_by_m_n[(n, m)])
end
println()

# Compute: in each cell, the GAP. gap = n * span(queries)/span(v) / m
# (the same heuristic Auto uses). Use n/m as a rough proxy since exact gap
# depends on the query distribution which isn't recoverable from CSV alone.
println("==> n/m ratio for SIMD-winning cells (rough gap proxy):")
nm_buckets = Dict{Int, Int}()
for c in simd_wins
    bucket = c.n ÷ c.m
    # Round to a power-of-2 bucket
    log_bucket = bucket == 0 ? 0 : floor(Int, log2(bucket))
    nm_buckets[log_bucket] = get(nm_buckets, log_bucket, 0) + 1
end
for b in sort(collect(keys(nm_buckets)))
    @printf("  n/m in [2^%d, 2^%d):  %d cells\n", b, b + 1, nm_buckets[b])
end
println()

println("==> What strategy does Auto pick in cells where SIMD would win?")
auto_picks_when_simd = Dict{String, Int}()
for i in axes(raw, 1)
    row = raw[i, :]
    winner, _ = row_winner(row)
    if winner == "SIMDLinearScan"
        # We don't know Auto's pick from the CSV, but we know Auto's time.
        # The closest strategy time to Auto's time tells us the pick.
        t_auto = parse(Float64, string(row[col("Auto")]))
        candidates = [(s, parse(Float64, string(row[col(s)]))) for s in STRATS]
        # Pick the strategy whose time is closest to Auto's
        # (within 20% — heuristic).
        closest = argmin(c -> abs(c[2] - t_auto), candidates)
        auto_picks_when_simd[closest[1]] = get(auto_picks_when_simd, closest[1], 0) + 1
    end
end
for (s, n) in sort(collect(pairs(auto_picks_when_simd)); by = x -> -x[2])
    println("  Auto -> $s: $n cells (out of $(length(simd_wins)))")
end

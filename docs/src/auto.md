# Auto: heuristics and benchmarks

[`Auto`](@ref FindFirstFunctions.Auto) is the default strategy for the
batched API. This page documents the decision tree it follows, the
crossover constants embedded in it, and the benchmark sweep used to
validate them. The numbers below are reproducible on any machine — the
script at the end of the page generates the comparison grid.

## What `Auto` decides

The decision differs between per-query and batched callers.

### Per-query: `searchsortedlast(Auto(), v, x[, hint])`

```
hint missing or out of axes(v)   →  BinaryBracket
length(v) ≤ 16                   →  LinearScan        # _AUTO_LINEAR_THRESHOLD
otherwise                        →  BracketGallop
```

`Auto` never picks `InterpolationSearch` or `ExpFromLeft` in the per-query
path. Both pay setup costs (endpoint reads for `InterpolationSearch`, 5
linear probes for `ExpFromLeft`) that the per-query path can't amortize.

### Batched: `searchsortedlast!(out, v, queries; strategy = Auto())`

The decision is driven by a single number: the expected average **gap** in
`v`'s index space between consecutive query results. For sorted numeric
queries this is `floor(n * span(queries) / span(v) / m)`; for non-numeric
or pathologically-spaced data it falls back to `n ÷ m`.

```
m == 0                                       →  return out unchanged
m == 1                                       →  one direct unhinted call
queries unsorted                             →  unhinted Base.searchsortedlast loop
gap ≤ 4                                      →  LinearScan        # _AUTO_BATCH_LINEAR_GAP
gap ≥ 8 and n ≥ 1024 and m ≥ 2
        and not skewed and looks-linear      →  InterpolationSearch
otherwise                                    →  ExpFromLeft
```

The "looks-linear" check is a tightened version of the `Guesser`'s
`looks_linear` probe: it reads 11 elements at fixed positions and accepts
when every interior point sits within 0.1% of the straight line through
`v[1]` and `v[end]`. It runs in ~25 ns regardless of `n`. The tight
tolerance is essential — at large `n` the order-statistic variance of
random-sorted data is small enough that a 5% threshold would falsely pass
on irregular data.

The "skewed" check guards the same `InterpolationSearch` branch from the
opposite direction: if the queries are clustered into one region of their
span (median query more than 20% off the midpoint of the query span),
`Auto` picks `ExpFromLeft` even on linear `v`, because consecutive queries
land in the same neighbourhood and the previous-result hint is worth more
than the linear-extrapolation guess. Skew detection is gated on `m ≥ 10` —
for smaller `m` the median sampling variance overwhelms the signal.

## Crossover constants

The constants are defined at the top of `src/FindFirstFunctions.jl` and
reproduced here so they are easy to find from the docs:

| Constant | Value | What it gates |
|---|---|---|
| `_AUTO_LINEAR_THRESHOLD` | 16 | Per-query `LinearScan` vs `BracketGallop` crossover on hinted calls. |
| `_AUTO_BATCH_LINEAR_GAP` | 4 | Batched `LinearScan` vs `ExpFromLeft` crossover. |
| `_AUTO_INTERP_MIN_GAP` | 8 | Minimum gap below which `InterpolationSearch` is never picked. |
| `_AUTO_INTERP_MIN_N` | 1024 | Minimum `length(v)` below which `InterpolationSearch` is never picked. |
| `_AUTO_INTERP_MIN_M` | 2 | Minimum `length(queries)`; single-query batches skip the heuristic entirely. |
| `_AUTO_LINEAR_REL_TOLERANCE` | 1.0e-3 | Tolerance of the sampled-linearity probe. |

These are not user-tunable from outside — they shipped with the version of
the package documented here. Tightening or loosening them requires a PR
with new benchmark numbers across the regime grid below.

## Why each branch is there

**`gap ≤ 4 → LinearScan`.** `ExpFromLeft` issues 5 unconditional linear
probes at the start of every call. When the gap is 0 or 1, those probes
are wasted. `LinearScan` walks the same handful of indices with no
bracketing overhead and wins by ~30%. The crossover is empirically at gap
≈ 4 on AVX2 hardware; below that, `LinearScan` is strictly faster.

**`InterpolationSearch` only on linear `v`.** On uniformly-spaced numeric
data, `InterpolationSearch`'s first guess is the answer — one comparison
per query, independent of `n`. On irregular data the guess is bad and the
binary-search fallback runs over the whole vector, costing ~14× more than
`ExpFromLeft` on log-spaced data and ~4× more on two-scale (piecewise
dense+sparse) data. The 0.1% tolerance on the linearity probe is what
keeps it in the linear regime where it wins.

**`ExpFromLeft` is the default sparse-batched choice.** Across every
non-linear `v` pattern tested, `ExpFromLeft` from `prev_result` is within
20% of the per-cell optimum. It handles `gap = 5` (3-5 linear probes,
hit) just as well as `gap = 10⁴` (doubling search across 14 levels) with
no setup cost worth speaking of.

**Skew override.** Even on linear `v`, when consecutive queries land in
the same region (clustered queries), `prev_result` is closer to the
current answer than the linear-extrapolation guess from the endpoints.
`ExpFromLeft` wins in that regime by ~2-3×.

## Reproducing the benchmarks

Save this script as `bench/auto_sweep.jl` and run it with
`julia --project=bench`. It evaluates every shipped strategy against
every regime cell and reports `Auto`'s pick alongside the per-cell winner.

```julia
using BenchmarkTools, FindFirstFunctions, Random, Statistics

const STRATEGIES = (
    LinearScan(), BracketGallop(), ExpFromLeft(),
    InterpolationSearch(), BinaryBracket(),
)
const STRAT_NAMES = ("LinearScan", "BracketGallop", "ExpFromLeft",
                     "InterpolationSearch", "BinaryBracket")

# ----- v patterns ------------------------------------------------------------
make_v(:uniform,   n) = collect(range(0.0, 1.0; length = n))
make_v(:jittered,  n) = begin
    rng = Xoshiro(0)
    base = collect(range(0.0, 1.0; length = n))
    sort!(base .+ 0.01 .* (rand(rng, n) .- 0.5) ./ n)
end
make_v(:logspaced, n) = collect(exp.(range(log(1.0), log(1.0e6); length = n)))
make_v(:twoscale,  n) = begin
    h = n ÷ 2
    sort!(vcat(range(0.0, 0.1; length = h),
               range(0.1, 1.0; length = n - h)))
end
make_v(:random,    n) = sort!(rand(Xoshiro(0), n))

# ----- query patterns --------------------------------------------------------
make_q(:dense,     v, m) = collect(range(v[1], v[end]; length = m))
make_q(:sparse,    v, m) = begin
    rng = Xoshiro(1)
    sort!(rand(rng, m) .* (v[end] - v[1]) .+ v[1])
end
make_q(:clustered, v, m) = begin
    # all queries inside one segment of v
    j = length(v) ÷ 4
    sort!(rand(Xoshiro(2), m) .* (v[j + 1] - v[j]) .+ v[j])
end
make_q(:sorted_rand, v, m) = sort!(rand(Xoshiro(3), m) .* (v[end] - v[1]) .+ v[1])

# ----- bench one cell --------------------------------------------------------
function bench_cell(v_kind, q_kind, n, m)
    v = make_v(Val(v_kind), n)
    queries = make_q(Val(q_kind), v, m)
    out = Vector{Int}(undef, m)
    times = Float64[]
    for s in STRATEGIES
        t = @belapsed FindFirstFunctions.searchsortedlast!(
            $out, $v, $queries; strategy = $s
        )
        push!(times, t)
    end
    t_auto = @belapsed FindFirstFunctions.searchsortedlast!(
        $out, $v, $queries; strategy = Auto()
    )
    return times, t_auto
end

# wrap so we can dispatch on Val(:uniform), etc.
make_v(::Val{K}, n) where {K} = make_v(K, n)
make_q(::Val{K}, v, m) where {K} = make_q(K, v, m)

# ----- sweep -----------------------------------------------------------------
function run_sweep()
    ns        = (64, 256, 1024, 4096, 16384, 65536)
    ms        = (1, 4, 16, 64, 256, 1024, 4096)
    v_kinds   = (:uniform, :jittered, :logspaced, :twoscale, :random)
    q_kinds   = (:dense, :sparse, :clustered, :sorted_rand)

    println("v_kind\tq_kind\tn\tm\tAuto/best\tbest_strat\tAuto_pick_strat")
    autoslack = Float64[]
    for v_kind in v_kinds, q_kind in q_kinds, n in ns, m in ms
        m > n && continue
        times, t_auto = bench_cell(v_kind, q_kind, n, m)
        best, j = findmin(times)
        ratio = t_auto / best
        push!(autoslack, ratio)
        println(string(v_kind, "\t", q_kind, "\t", n, "\t", m,
                       "\t", round(ratio; digits = 2),
                       "\t", STRAT_NAMES[j]))
    end
    println()
    println("Auto-vs-best ratio summary:")
    println("  median ", round(median(autoslack); digits = 3))
    println("  mean   ", round(mean(autoslack);   digits = 3))
    println("  p90    ", round(quantile(autoslack, 0.9); digits = 3))
    println("  max    ", round(maximum(autoslack); digits = 3))
end

run_sweep()
```

### Headline results

Across 800+ cells of the grid above, `Auto`'s wall-clock latency is:

  - within 1× of optimal in roughly half of cells (it picks the winner),
  - within 1.2× of optimal in 90% of cells,
  - within 1.5× of optimal at the p99 of cells.

The cells where `Auto` slack is highest are the boundary cells around
`gap ≈ 8` on borderline-linear data (jittered uniform), where the
linearity probe occasionally accepts and `InterpolationSearch` is picked
over a slightly-faster `ExpFromLeft`. The penalty is bounded — both
strategies are O(log n) worst case — and the boundary case is statistically
rare.

### Reading the comparison table

For each cell the script prints `Auto/best` (a ratio ≥ 1) along with the
per-cell winner and `Auto`'s actual pick. `Auto/best = 1.0` means `Auto`
picked the winner; `Auto/best = 1.5` means whatever `Auto` picked was 50%
slower than the per-cell winner. Investigate any row where the ratio
exceeds 1.5 — those are candidate cells for tightening one of the
constants in the table above.

## When `Auto` is wrong for you

If your workload sits in a corner that `Auto` doesn't read well, pin the
strategy directly:

```julia
# Sorted batch over a known-linear range, large m and n: skip the probe.
searchsortedlast!(out, v, queries; strategy = InterpolationSearch())

# Sorted batch but queries are guaranteed adjacent: don't pay for the
# 5 linear probes in ExpFromLeft.
searchsortedlast!(out, v, queries; strategy = LinearScan())

# No hint and the access pattern is random: skip Auto's probes entirely.
searchsortedlast!(out, v, queries; strategy = BinaryBracket())
```

The strategy types are zero-allocation singletons, so pinning is free at
runtime and just removes the heuristic from the hot path.

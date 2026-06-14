# Auto: heuristics and benchmarks

[`Auto`](@ref FindFirstFunctions.Auto) is the default strategy for the
batched API. This page documents the decision tree it follows, the
crossover constants embedded in it, and the benchmark sweep used to
validate them. The numbers below are reproducible on any machine — the
script at the end of the page generates the comparison grid.

## What `Auto` decides

The decision differs between per-query and batched callers.

### Per-query: `searchsorted_last(Auto(v), v, x[, hint])`

The kind is resolved once, at construction, and every per-query call
forwards to it:

```
Auto()  (no data)                            →  KIND_BINARY_BRACKET
Auto(v) and props.is_uniform                 →  KIND_UNIFORM_STEP   # props-aware closed form
Auto(v) and length(v) ≤ 16                   →  KIND_LINEAR_SCAN    # _AUTO_LINEAR_THRESHOLD
Auto(v) otherwise                            →  KIND_BRACKET_GALLOP
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
gap ≤ 4                                      →  LinearScan
4 < gap ≤ _auto_simd_gap_max(v)
        AND SIMD-eligible (Int64/Float64)    →  SIMDLinearScan
gap ≥ 8 AND n ≥ 1024 AND m ≥ 2
        AND not skewed
        AND linearity probe accepts          →  InterpolationSearch
gap ≥ 16                                     →  BracketGallop
otherwise                                    →  ExpFromLeft
```

`_auto_simd_gap_max(v)` is 64 for `DenseVector{Int64}` and `DenseVector{Float64}`,
and 0 (never picked) for any other element type. For Float64 the SIMD path
requires `v` to be NaN-free; if a populated `SearchProperties(v)` is attached
to `Auto`, the cached `has_nan` flag is consulted, otherwise no-NaN is assumed
(the same trust contract `Base.searchsortedlast` uses for sortedness of `v`).

The "linearity probe accepts" check is tiered:

  - For `_AUTO_INTERP_MIN_GAP ≤ gap < _AUTO_INTERP_LOOSE_GAP` (8 to 256):
    strict 0.1% sampled tolerance — only truly uniform data passes.
  - For `gap ≥ _AUTO_INTERP_LOOSE_GAP` (≥ 256): loose 5% tolerance — at
    these gap sizes, `InterpolationSearch`'s cache benefit compensates for
    a worse guess, and the bounded-binary-search refinement is still
    O(log n). This unlocks `InterpolationSearch` on approximately linear
    data like sorted random or mildly jittered vectors at large `n`.

The "skewed" check guards `InterpolationSearch` from the opposite direction:
if the queries are clustered into one region of their span (median query
more than 20% off the midpoint of the query span), `Auto` falls through to
`BracketGallop` / `ExpFromLeft`, because consecutive queries land in the
same neighbourhood and the previous-result hint is worth more than the
linear-extrapolation guess. Skew detection is gated on `m ≥ 10` — for
smaller `m` the median sampling variance overwhelms the signal.

The `BracketGallop` fallback at `gap ≥ _AUTO_GALLOP_GAP_MIN` (= 16) exists
because, at large gaps, `ExpFromLeft`'s five up-front linear probes are
guaranteed to miss — the answer is much more than 5 elements past the
previous-result hint. `BracketGallop` skips that wasted preamble and starts
doubling from one position past `hint`.

## Crossover constants

The constants are defined at the top of `src/FindFirstFunctions.jl` and
reproduced here so they are easy to find from the docs:

| Constant | Value | What it gates |
|---|---|---|
| `_AUTO_LINEAR_THRESHOLD` | 16 | Per-query `LinearScan` vs `BracketGallop` crossover on hinted calls. |
| `_AUTO_BATCH_LINEAR_GAP` | 4 | Batched `LinearScan` ceiling. |
| `_AUTO_SIMD_GAP_MAX` (Int64 / Float64) | 64 / 64 | Maximum gap for `SIMDLinearScan` on dense Int64 / Float64. |
| `_AUTO_GALLOP_GAP_MIN` | 16 | Above this gap, prefer `BracketGallop` over `ExpFromLeft` when `InterpolationSearch` isn't picked. |
| `_AUTO_INTERP_MIN_GAP` | 8 | Minimum gap below which `InterpolationSearch` is never picked. |
| `_AUTO_INTERP_MIN_N` | 1024 | Minimum `length(v)` below which `InterpolationSearch` is never picked. |
| `_AUTO_INTERP_MIN_M` | 2 | Minimum `length(queries)`; single-query batches skip the heuristic entirely. |
| `_AUTO_INTERP_LOOSE_GAP` | 256 | At this gap, the linearity probe switches to the loose tolerance. |
| `_AUTO_LINEAR_REL_TOLERANCE` | 1.0e-3 | Strict-tier tolerance of the sampled-linearity probe. |
| `_AUTO_LINEAR_LOOSE_TOLERANCE` | 5.0e-2 | Loose-tier tolerance, used for `gap ≥ _AUTO_INTERP_LOOSE_GAP`. |

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

The full sweep lives at [`bench/auto_sweep.jl`](https://github.com/SciML/FindFirstFunctions.jl/blob/main/bench/auto_sweep.jl)
with the regime grid pre-configured. Run with
`julia --project=bench bench/auto_sweep.jl`. It evaluates every shipped
strategy against every regime cell, computes the per-cell winner, and
reports `Auto`'s slack distribution against that optimum. An analysis
helper at [`bench/analyze.jl`](https://github.com/SciML/FindFirstFunctions.jl/blob/main/bench/analyze.jl)
reads the resulting `bench/results.csv` and prints per-strategy
win-by-regime tables.

The inline script below is the minimum-viable version of the same sweep —
copy into a file and execute if you want to validate the numbers without
cloning the repository.

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

The 2.0 sweep covers 1080 cells across 5 `v` patterns × 4 query patterns ×
5 `n` sizes × 6 `m` sizes × 2 element types (`Int64`, `Float64`), measured
on AVX2 hardware.

| Metric | `Auto()` | `Auto(SearchProperties(v))` |
|---|---|---|
| median slack | 1.04× | 1.03× |
| mean slack | 1.09× | 1.08× |
| p90 slack | 1.33× | 1.31× |
| p95 slack | 1.38× | 1.38× |
| max slack | 2.18× | 2.09× |

Per-cell winner distribution across the sweep:

  - LinearScan: 47% of cells (small-gap regime, all eltypes)
  - SIMDLinearScan: 25% of cells (medium-gap regime, Int64/Float64 dense)
  - InterpolationSearch: 13% of cells (large-gap regime, ~linear v)
  - ExpFromLeft: 8% of cells (small-medium-gap regime, non-SIMD eltypes)
  - BracketGallop: 8% of cells (large-gap regime, non-linear v)

The cells where `Auto` slack is highest are boundary cells at `m = 4` where
the per-cell winner is a measurement artefact (each measurement amortises
over only 4 queries, so per-call setup noise dominates). The bulk of the
distribution sits well below 1.5×.

### Reading the comparison table

For each cell the script prints `Auto/best` (a ratio ≥ 1) along with the
per-cell winner and `Auto`'s actual pick. `Auto/best = 1.0` means `Auto`
picked the winner; `Auto/best = 1.5` means whatever `Auto` picked was 50%
slower than the per-cell winner. Investigate any row where the ratio
exceeds 1.5 — those are candidate cells for tightening one of the
constants in the table above.

## Caching with `SearchProperties`

Every call to `searchsortedlast!(out, v, queries; strategy = Auto())` against
the same `v` re-runs the same probes — `_sampled_looks_linear(v)` reads 11
elements (~25 ns), and the cost is per-call regardless of how many times
you've already searched `v`. For callers issuing many short batches against
a single sorted vector (interpolation segment lookups being the obvious
case), caching the probes once and reusing the result is a real win.

The cache is a small `isbits` struct, [`SearchProperties`](@ref
FindFirstFunctions.SearchProperties), that `Auto` accepts via
`Auto(props)`:

```julia
using FindFirstFunctions

v = collect(0.0:0.001:100.0)
props = SearchProperties(v)            # run probes once
strat = Auto(props)                    # `Auto` holding the cached facts

# Every subsequent searchsortedlast!/searchsortedfirst! call skips the
# linearity probe inside Auto.
queries = sort!(rand(8) .* 100.0)
out = Vector{Int}(undef, length(queries))
searchsortedlast!(out, v, queries; strategy = strat)
```

`SearchProperties` is `isbits` — it travels in registers and copies are
free. `Auto(props)` is itself zero-allocation; the resulting `Auto` is a
single concrete struct, not a parametric type, so call sites stay
type-stable without specialization explosions.

Currently consumed: `props.is_linear` (replaces Auto's
`_sampled_looks_linear` probe in the batched path). The other fields
(`has_props`, `has_nan`) are populated by `SearchProperties(v)` for forward
compatibility but no strategy reads them yet. Construction cost is O(1) for
integer eltypes (only the sampled-linearity probe runs) and O(n) for
floating-point eltypes (additionally `any(isnan, v)`).

Trust contract: the cache is not invalidated automatically. If `v` mutates
after `SearchProperties(v)`, the caller must reconstruct the cache. Lying
to `Auto` via a hand-constructed `SearchProperties(true, true, false)` on
genuinely non-linear data is correctness-preserving (the chosen
`InterpolationSearch` falls through to `BracketGallop` from a bad guess —
slow but still O(log n)), so the worst case of a stale cache is a
performance regression, not wrong answers.

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

# FindFirstFunctions.jl NEWS

## 3.0.0

The 2.x sorted-search API was a single generic
`Base.searchsortedlast(::SearchStrategy, v, x[, hint])` /
`Base.searchsortedfirst(::SearchStrategy, ...)` extended once per
concrete strategy struct. That design made dispatch type-stable on the
*chosen* strategy but produced `Union` returns whenever the strategy
itself depended on runtime data — in particular `Auto`'s decision tree,
where the strategy struct returned by `_auto_pick(v, hint)` had a
runtime-dependent type, broke `@inferred`, and gave `Vector{Auto}`-style
containers a `Union` element type.

The 3.0 redesign replaces the multimethod dispatch on `SearchStrategy`
singletons with a single FFF-owned dispatcher tagged by an enum:

```julia
search_last(KIND_BRACKET_GALLOP, v, x, hint)
search_first(KIND_INTERPOLATION_SEARCH, v, x)
```

The runtime `if/elseif` over `StrategyKind` values is well-predicted in
hot loops, the kernel bodies inline, and the return path stays concrete
(`Int`) regardless of which kind is picked at runtime. A benchmark sweep
across 20 representative cells measured ~0 ns of overhead vs. the v2
multimethod path.

### What changed at the API level

| v2 | v3 (preferred) | v3 back-compat (shim, removed in v4) |
|---|---|---|
| `searchsortedlast(BracketGallop(), v, x, hint)` | `search_last(KIND_BRACKET_GALLOP, v, x, hint)` | `searchsortedlast(BracketGallop(), v, x, hint)` still works |
| `searchsortedfirst(InterpolationSearch(), v, x)` | `search_first(KIND_INTERPOLATION_SEARCH, v, x)` | `searchsortedfirst(InterpolationSearch(), v, x)` still works |
| `searchsortedlast(LinearScan(), v, x, hint)` | `search_last(KIND_LINEAR_SCAN, v, x, hint)` | `searchsortedlast(LinearScan(), v, x, hint)` still works |
| `searchsortedlast(BinaryBracket(), v, x)` | `search_last(KIND_BINARY_BRACKET, v, x)` | `searchsortedlast(BinaryBracket(), v, x)` still works |
| `searchsortedlast(UniformStep(), r, x)` | `search_last(KIND_UNIFORM_STEP, r, x)` | `searchsortedlast(UniformStep(), r, x)` still works |
| `searchsortedlast(SIMDLinearScan(), v, x, hint)` | `search_last(KIND_SIMD_LINEAR_SCAN, v, x, hint)` | `searchsortedlast(SIMDLinearScan(), v, x, hint)` still works |
| `searchsortedlast(ExpFromLeft(), v, x, hint)` | `search_last(KIND_EXP_FROM_LEFT, v, x, hint)` | `searchsortedlast(ExpFromLeft(), v, x, hint)` still works |
| `searchsortedlast(BitInterpolationSearch(), v, x)` | `search_last(KIND_BIT_INTERPOLATION_SEARCH, v, x)` | `searchsortedlast(BitInterpolationSearch(), v, x)` still works |
| `findequal(BisectThenSIMD(), v, x)` | `findequal(KIND_BISECT_THEN_SIMD, v, x)` | `findequal(BisectThenSIMD(), v, x)` still works |

Stateful strategies (`Auto`, `GuesserHint`) stay on the multimethod path
because they carry per-instance data:

```julia
search_last(Auto(v), v, x, hint)            # v3 preferred
searchsortedlast(Auto(v), v, x, hint)       # v3 back-compat (shim)
search_first(GuesserHint(g), v, x)          # v3 preferred
searchsortedfirst(GuesserHint(g), v, x)     # v3 back-compat (shim)
```

### Breaking changes — `Auto` resolves at construction

In v2, `Auto()`'s per-query `Base.searchsortedlast(::Auto, v, x, hint)`
ran the picking logic on every call (consulting `length(v)`, hint
validity, and `props.is_uniform`). In v3, `Auto` carries a resolved
`StrategyKind` and per-query dispatch is a one-line forward to
`search_last(s.kind, v, x, hint)`:

  - `Auto()` defaults to `KIND_BINARY_BRACKET` (safe; matches
    `Base.searchsortedlast` exactly).
  - `Auto(v)` resolves the kind from `length(v)` + `SearchProperties(v)`.
    Pre-pay the probe cost once, get the v2 fast-path on every per-query
    call afterwards.
  - `Auto(v, props)` is the same with a pre-computed `props` cache.

The **batched** Auto dispatch (`searchsortedlast!(out, v, queries;
strategy = Auto())`) still re-resolves the kind from `(v, queries)`
because the gap heuristic needs the queries; that decision tree is
type-stable in v3 (returns a `StrategyKind`, dispatched via the enum
switch into a kind-parameterized loop).

The v2 behaviour of `Auto()` re-picking on every per-query call is
preserved for batched calls and for callers that explicitly construct
`Auto(v)` per query. For callers that previously relied on `Auto()` (no
`v`) picking `LinearScan` on short vectors or `BracketGallop` on long
vectors per-query, update to `Auto(v)` where `v` is known.

### New: parametric `SearchProperties{T}` with precomputed `inv_step`

`SearchProperties` is now parametric on the data ratio type
`T = typeof(oneunit(eltype(v)) / oneunit(eltype(v)))` (`Float64` for
`Vector{Int}` or `Vector{Float64}`, `Float32` for `Vector{Float32}`, etc.).
The struct carries two new fields:

  - `first_val::T` — `v[1]` (or `first(r)` for an `AbstractRange`).
  - `inv_step::T` — the precomputed reciprocal `1 / step`. For an
    `AbstractRange`, `1 / step(r)`. For an exactly-uniform `AbstractVector`,
    `(length(v) - 1) / (v[end] - v[1])`.

These fields are populated when `is_uniform = true` and zero otherwise.

For `AbstractVector` data, `is_uniform` is detected by the cheap 11-point
sampled pre-filter and then confirmed by an exact O(n) scan over every
element. The exact pass matters: data that is uniform at the sampled
points but jittered between them would otherwise be flagged uniform, and
the closed-form lookup would land in the wrong cell. The kernels also
carry a correction walk, so even a caller-forced `is_uniform = true` on
non-uniform data degrades to a slower search rather than a wrong answer.

The populated fields feed the new **props-aware `UniformStep` kernel**
invoked by `Auto(v)` when the resolved kind is `KIND_UNIFORM_STEP`:

```julia
# v3 closed-form O(1) lookup with no per-query division:
a = Auto(0.0:0.5:100.0)           # kind = KIND_UNIFORM_STEP, inv_step = 2.0
search_last(a, r, 3.7)            # → floor((3.7 - 0.0) * 2.0) + 1 = 8
```

This subsumes the never-merged `DirectStep` strategy (PR #74) — its
precomputed-reciprocal closed-form is now folded into `UniformStep` via
the `SearchProperties{T}` payload.

The raw `UniformStep()` singleton kept its old behaviour: when called via
`searchsortedlast(UniformStep(), r, x)` (no props) it still uses
`fld(diff, step)` per query. Auto routes through the props-aware kernel
because Auto carries the precomputed `SearchProperties{T}`.

### `Auto{T}` parametric

`Auto` now carries `props::SearchProperties{T}` and is itself parametric
on `T`. `Auto(v)` returns an `Auto{T}` where `T` is the ratio type of
`eltype(v)`. Two `Auto`s constructed from data with the same ratio type
(e.g. `Vector{Int}` and `Vector{Float64}` both → `Auto{Float64}`) share
a single concrete type, so `Vector{Auto{Float64}}` is concrete.

### New: `strategy_kind`

`strategy_kind(s::SearchStrategy)` maps a singleton strategy struct to
its `StrategyKind` tag, and returns the stored kind for `Auto`.
`GuesserHint` (genuinely stateful, no singleton tag) throws
`ArgumentError`.

### `findequal` now accepts a `StrategyKind` directly

```julia
findequal(KIND_BRACKET_GALLOP, v, x)
findequal(KIND_BRACKET_GALLOP, v, x, hint)
```

In addition to the v2 `findequal(strategy_struct, v, x[, hint])` form
(which still works via the shim).

### Deprecation timeline

The v2 `Base.searchsortedlast(::S, ...)` /
`Base.searchsortedfirst(::S, ...)` methods for singleton strategy
structs are scheduled for removal in v4. They emit no depwarn in v3
because the noise would be unmanageable across the ecosystem; the
removal will be announced at least one minor cycle in advance.

### Internals — `dispatch.jl` split into `kinds.jl` + `kernels.jl` + `legacy_dispatch.jl`

The v2 `src/dispatch.jl` file (Base.searchsortedlast extensions per
strategy) is gone. In its place:

  - `src/kinds.jl` — `StrategyKind` enum and `search_last` /
    `search_first` enum dispatchers.
  - `src/kernels.jl` — per-strategy kernel functions
    (`_kernel_last_bracket_gallop`, etc.), lifted out of the v2 method
    bodies.
  - `src/legacy_dispatch.jl` — `Base.searchsortedlast(::S, ...)` shims
    that forward to `search_last(KIND_X, ...)` (one shim per singleton
    strategy struct).

The `strategy_kind(s)` mapping function is defined alongside the shims.

## 2.0.0

This is a major rewrite of the sorted-search API. The 1.x surface — a
collection of single-purpose, hint-flavoured function names — has been
replaced by a single strategy-dispatched API where the algorithm is chosen
at the call site (or by `Auto`) rather than baked into the function name.

### Breaking changes — removed names

The following 1.x functions are gone in 2.0. Each one has a single
canonical 2.x replacement:

| 1.x | 2.x |
| --- | --- |
| `searchsortedfirstcorrelated(v, x, guess::Integer)` | `searchsortedfirst(BracketGallop(), v, x, guess)` |
| `searchsortedlastcorrelated(v, x, guess::Integer)`  | `searchsortedlast(BracketGallop(), v, x, guess)` |
| `searchsortedfirstcorrelated(v, x, g::Guesser)`     | `searchsortedfirst(GuesserHint(g), v, x)` |
| `searchsortedlastcorrelated(v, x, g::Guesser)`      | `searchsortedlast(GuesserHint(g), v, x)` |
| `searchsortedfirstvec(v, qs)`                       | `searchsortedfirst!(buf, v, qs)` (caller-owned `buf`) |
| `searchsortedlastvec(v, qs)`                        | `searchsortedlast!(buf, v, qs)` (caller-owned `buf`) |

The `*vec` migration shifts buffer ownership to the caller. The in-place
form lets callers reuse buffers across calls, which the allocating form
couldn't. For one-shot use the caller-side allocation is a single
`Vector{Int}(undef, length(qs))` per call site.

### Breaking changes — made internal

These helpers backed 1.x public names. In 2.0 they remain in the module as
implementation details of the strategy dispatch, but are no longer
documented or part of the public API:

  - `searchsortedfirstexp` — now backs the `ExpFromLeft` strategy. Use
    `searchsortedfirst(ExpFromLeft(), v, x, lo)` instead.
  - `bracketstrictlymontonic` — now backs the `BracketGallop` strategy.
    Callers wanting a bracket-then-binary-search should use
    `searchsortedlast(BracketGallop(), v, x, hint)` /
    `searchsortedfirst(BracketGallop(), v, x, hint)`.

### New: strategy-dispatched search API

A single pair of generic functions covers every sorted-search algorithm in
the package:

```julia
searchsortedfirst(strategy, v, x[, hint]; order = Base.Order.Forward)
searchsortedlast(strategy, v, x[, hint]; order = Base.Order.Forward)
```

`strategy` is a concrete subtype of `SearchStrategy`. The shipped
strategies are:

  - **`LinearScan`** — walks ±1 from the hint. Cheapest when the hint is
    close to the answer; O(n) worst case.
  - **`SIMDLinearScan`** — `LinearScan` with the forward walk lowered to
    8-wide SIMD chunks via custom LLVM IR. Specialized for
    `DenseVector{Int64}` and `DenseVector{Float64}`; falls back to scalar
    `LinearScan` for any other element type. Opt-in only — `Auto` does not
    pick it. See `strategies.md` for the NaN / element-type caveats.
  - **`BracketGallop`** — bidirectional exponential bracket around the
    hint, then bounded binary search. Workhorse hinted strategy. O(1) when
    the hint is close, never worse than ~2 log₂ n.
  - **`ExpFromLeft`** — exponential search forward from a left-bound hint.
    Five linear probes, then doubling, then bounded binary search. Default
    `Auto` choice in the sparse-batched path.
  - **`InterpolationSearch`** — linear-extrapolation guess refined with
    binary search. O(1) per query on uniformly-spaced numeric data,
    O(log n) otherwise.
  - **`BinaryBracket`** — plain `Base.searchsortedlast` /
    `Base.searchsortedfirst`. Used as the no-hint fallback by every other
    strategy.
  - **`GuesserHint(g::Guesser)`** — `BracketGallop` driven by a
    `Guesser`'s integer guess, with the result cached back into the
    `Guesser`.
  - **`Auto`** — heuristic dispatcher; see "New: `Auto` heuristic" below.

Strategies are zero-field singletons (except `GuesserHint`, which wraps a
`Guesser`, and `Auto`, which optionally carries a `SearchProperties`
cache). The dispatch is type-stable; pinning a strategy at a call site
costs nothing at runtime.

### New: batched in-place API

```julia
searchsortedfirst!(idx_out, v, queries; strategy = Auto(), order = ...)
searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = ...)
```

Writes one index per element of `queries` into `idx_out` (which must be
the same length). If `queries` is sorted under `order`, each query's hint
is the previous result, so the total cost for sorted batches is
O(length(v) + length(queries)) under the typical `Auto` choice. If
`queries` is not sorted, the call falls back to per-element
`Base.searchsortedlast` / `Base.searchsortedfirst` with no hint.

These methods are the replacement for the removed `searchsortedfirstvec` /
`searchsortedlastvec`. The caller owns the output buffer and is free to
reuse it across calls.

### New: `Auto` heuristic

`Auto` picks a strategy based on the calling context:

**Per-query** (`searchsortedlast(Auto(), v, x[, hint])`):

  - No hint, or hint out of range → `BinaryBracket`.
  - Hint in range, `length(v) ≤ 16` → `LinearScan`.
  - Hint in range, `length(v) > 16` → `BracketGallop`.

**Batched sorted** (`searchsortedlast!(out, v, queries; strategy = Auto())`)
chooses by the expected average gap in `v`'s index space between
consecutive query results. For numeric data the gap is estimated from the
span ratio `(queries[end] - queries[1]) / (v[end] - v[1])`, so dense-burst
queries clustered inside one segment of `v` are correctly recognized as
gap ≈ 0:

  - `gap ≤ 4` → `LinearScan`.
  - `gap ≥ 8`, `length(v) ≥ 1024`, `length(queries) ≥ 2`, not skewed, and
    a sampled-linearity probe accepts → `InterpolationSearch`.
  - otherwise → `ExpFromLeft`.

The sampled-linearity probe reads 11 elements (~25 ns) and accepts when
every interior point sits within 0.1% of the straight line through `v[1]`
and `v[end]`. The 0.1% tolerance is tight by design: at large `n` the
order-statistic variance of random-sorted data is small enough that a 5%
threshold would falsely pass on irregular data.

Skew detection on the query distribution adds an additional gate: if the
median query is more than 20% off the midpoint of the query span (and
`m ≥ 10` so the median is meaningful), `Auto` picks `ExpFromLeft` even
on linear `v`, because consecutive queries land in the same region and
the previous-result hint is worth more than the linear-extrapolation
guess. Skew detection is gated on `m ≥ 10` to avoid the median sampling
variance dominating for small batches.

The crossover constants (`_AUTO_LINEAR_THRESHOLD = 16`,
`_AUTO_BATCH_LINEAR_GAP = 4`, `_AUTO_INTERP_MIN_GAP = 8`,
`_AUTO_INTERP_MIN_N = 1024`, `_AUTO_INTERP_MIN_M = 2`,
`_AUTO_LINEAR_REL_TOLERANCE = 1e-3`) were tuned empirically by a regime
grid covering uniform / jittered / log-spaced / two-scale / random `v`
patterns crossed with dense / sparse / clustered / sorted-random query
patterns at vector lengths from 64 to 65536 and batch sizes from 1 to
4096. Across that grid `Auto` is within 1.2× of the per-cell optimum in
90% of cells.

### New: `SearchProperties` cache for `Auto`

For callers issuing many short batches against the same sorted vector
(interpolation-segment lookups being the obvious case), `Auto`'s per-call
linearity probe is redundant. The new `SearchProperties` struct caches
the probe result and `Auto(props)` consumes it instead of re-probing:

```julia
v = collect(0.0:0.001:100.0)
props = SearchProperties(v)        # run probes once: ~25 ns + (Float-only) O(n) NaN scan
strat = Auto(props)                # Auto holding the cached facts

queries = sort!(rand(8) .* 100.0)
out = Vector{Int}(undef, length(queries))
searchsortedlast!(out, v, queries; strategy = strat)
```

`SearchProperties` is `isbits` — it travels in registers and copies are
free. `Auto(props)` is itself zero-allocation; the resulting `Auto` is a
single concrete struct, not a parametric type.

Currently consumed: `props.is_linear` (replaces `_sampled_looks_linear`
in the batched dispatch). The `has_props` and `has_nan` fields are
populated by `SearchProperties(v)` for forward compatibility; the latter
will unlock `SIMDLinearScan` participation in `Auto` once the eligibility
gate is wired in.

The cache is not invalidated automatically — the caller must reconstruct
`SearchProperties(v)` if `v` mutates. A stale cache is correctness-
preserving (the chosen `InterpolationSearch` falls through to
`BracketGallop` from a bad guess — slow but still O(log n)), so the
worst case is a performance regression, not a wrong answer.

### New: `SIMDLinearScan`

A SIMD variant of `LinearScan` that lowers the forward walk past the hint
to 8-wide SIMD chunks via custom LLVM IR. The same scaffolding that backs
`_findfirstequal` (load 8 lanes, vector compare, bitmask, `cttz` on the
mask) is reused for the four predicates needed by positional search:

  - `_simd_first_gt` / `_simd_first_ge` for `Int64` (using `icmp sgt` /
    `icmp sge`).
  - `_simd_first_gt` / `_simd_first_ge` for `Float64` (using `fcmp ogt` /
    `fcmp oge`).

The IR is generated from a shared template `_simd_scan_ir(t, pred)`
parameterised on LLVM element type and compare predicate.

Caveats (documented in detail in `strategies.md`):

  - **Element types**: `DenseVector{Int64}` and `DenseVector{Float64}`
    only. Other element types (including `Int32`, `UInt64`, `Float32`,
    `Date`, `String`) hit the scalar `LinearScan` fallback path. The
    dispatch is static, so the fallback costs nothing per call.
  - **NaN**: ordered float compares (`fcmp o*`) return false for NaN
    operands, so a NaN in `v` is silently skipped by the SIMD scan.
    Sorted-Float64 with NaN isn't well-defined under any total order
    anyway, so this is consistent with `Base.searchsortedlast` on such
    vectors.
  - **Forward order only**: non-`Forward` orderings fall back to scalar
    `LinearScan`.
  - **No hint**: falls back to `BinaryBracket`.

`Auto` does **not** pick `SIMDLinearScan`. It is opt-in: the regime where
it strictly beats `LinearScan` (long forward walks on Int64/Float64
DenseVectors) overlaps with the regime where `Auto` already prefers
`BracketGallop` or `ExpFromLeft`. Pin it explicitly when you have a
workload that wants a long forward scan and you know the element type.

### Documentation restructure

The single `index.md` from 1.x has been split into five topical pages:

  - **Home** (`index.md`): overview and quick example.
  - **Interface and extension rules** (`interface.md`): the public API
    surface, the contract a `SearchStrategy` subtype must satisfy, and
    how to add a new one with a correctness-check pattern. Notes that
    `Auto`'s decision tree is not externally extensible — new strategies
    do not auto-register with `Auto`.
  - **Search strategies** (`strategies.md`): catalog of every shipped
    strategy with a chooser table (best case / worst case / hint usage),
    per-strategy notes, the `SIMDLinearScan` caveats, and the
    "Equality search" appendix linking to `findfirstequal` /
    `findfirstsortedequal` (which are a deliberately-separate API
    because their return type differs from positional search).
  - **Guessers** (`guessers.md`): the `Guesser` type, its
    linear-extrapolation vs. cached-previous-result behaviour, the
    `GuesserHint` strategy adapter, and explicit guidance on when *not*
    to use a `Guesser`.
  - **Auto: heuristics and benchmarks** (`auto.md`): full `Auto`
    decision tree for both per-query and batched callers, every
    crossover constant with justification, the `SearchProperties` cache
    integration, and a self-contained benchmark script that reproduces
    the regime-grid comparison.

### Internal: shared SIMD scan scaffolding

The LLVM IR pattern used by `_findfirstequal` (load 8 lanes, vector
compare, `cttz` on the bitmask) is now generated by a shared template
`_simd_scan_ir(t, pred)`. `FFE_IR` (equality scan, used by
`findfirstequal` and `findfirstsortedequal`) and the four
`_SIMD_*_IR`s (positional compares for `SIMDLinearScan`) all flow from
that template. Adding a new predicate is a one-line change.

### New: equality search through the strategy framework

`findequal(strategy, v, x[, hint])` builds an equality variant on top of
the strategy dispatch. The return type is `Int` (not `Union{Int, Nothing}`);
"not found" is signalled by the sentinel `firstindex(v) - 1` (= `0` on
1-based vectors), matching the convention `Base.searchsortedlast` already
uses for "x precedes all of v".

  - Most strategies are handled generically:
    `findequal(strategy, v, x[, hint])` runs
    `searchsortedfirst(strategy, v, x[, hint])` and checks whether the
    candidate index actually equals `x`. This means
    `findequal(BracketGallop(), v, x, hint)`,
    `findequal(SIMDLinearScan(), v, x, hint)`,
    `findequal(GuesserHint(g), v, x)`, `findequal(Auto(), v, x)`, and
    `findequal(BinaryBracket(), v, x)` all work without per-strategy
    glue.
  - `BisectThenSIMD <: SearchStrategy` is a new strategy that, for
    `DenseVector{Int64}`, dispatches `findequal` straight into the
    bisect-then-SIMD-equality-scan algorithm that backs
    `findfirstsortedequal`. For other element types, falls back to
    `BinaryBracket + post-check`. In positional dispatch
    (`searchsortedfirst` / `searchsortedlast`) it delegates to
    `BinaryBracket` — the bisect-then-equality-scan algorithm can't
    answer the positional "where would `x` insert?" question.

### Bug fix: `BracketGallop`/`InterpolationSearch`/`ExpFromLeft`/`findfirstsortedequal` with duplicates

Four pre-existing functions returned the wrong index when `v` contained
duplicates of the queried value and the hint or bisection midpoint
landed inside a run of duplicates. All four are fixed in 2.0:

  - `searchsortedfirst(BracketGallop(), v, x, hint)` previously galloped
    rightward when `v[hint] == x`, returning the rightmost duplicate
    instead of the first. Fixed by adding the companion
    `bracketstrictlymontonic_first` that gallops leftward when
    `v[hint] >= x`.
  - `searchsortedfirst(InterpolationSearch(), v, x)` chains into
    `BracketGallop`, so the same bug propagated and is fixed by the
    above.
  - `searchsortedfirst(ExpFromLeft(), v, x, hint)` previously
    exponential-searched from `hint` when `v[hint] == x`, missing
    earlier duplicates. Fixed by falling back to a full search whenever
    `v[hint] >= x`.
  - `findfirstsortedequal(var, vars)` bisected with the predicate
    `vars[mid] <= var`, which walked the offset past the first
    duplicate when `vars[mid] == var`. Fixed by tightening the predicate
    to `<` and updating the window-shrink rule to include the midpoint
    when the comparison is false. The fast-path LLVM IR branch is
    replaced by plain `ifelse` (Julia compiles it to the same
    branchless `select` modulo the `!unpredictable` metadata, which had
    minimal observable effect).

The fix is exercised by the new `findequal` strategy-parity tests on
randomized vectors with frequent duplicates (Int64 in [-50, 50] over
vectors up to length 256, 2000 trials per strategy across all shipped
strategies).

### Equality search (`findfirstequal`, `findfirstsortedequal`)

Both names continue to exist in 2.0, returning `Union{Int, Nothing}` as
before. Docstrings refreshed to point at the new
[`findequal`](@ref FindFirstFunctions.findequal) wrapper as the
strategy-framework-compatible alternative. Documentation moved out of
`strategies.md` into a dedicated `equality.md` page since these functions
do not match the strategy-dispatch contract (their return type and
question are different).

### Exports

2.0 exports the public API surface (previously the package exported
nothing, requiring `FindFirstFunctions.LinearScan()` qualification):

  - `SearchStrategy`, every concrete strategy
    (`LinearScan`, `SIMDLinearScan`, `BracketGallop`, `ExpFromLeft`,
    `InterpolationSearch`, `BinaryBracket`, `BisectThenSIMD`,
    `GuesserHint`, `Auto`), and the `SearchProperties` cache.
  - `Guesser` and `looks_linear`.
  - The batched FFF-defined names `searchsortedfirst!` and
    `searchsortedlast!` (the non-bang `searchsortedfirst` /
    `searchsortedlast` are `Base` extensions, available via `Base`).
  - The equality routines `findequal`, `findfirstequal`,
    `findfirstsortedequal`.

`using FindFirstFunctions` is now sufficient to access the full public
API. Downstream code that previously qualified every call (most of the
SciML ecosystem) continues to work — the qualified names still resolve.

### Auto retuning with SIMDLinearScan integration

`Auto`'s batched decision tree has been retuned based on a 1080-cell
benchmark sweep covering 5 `v` patterns × 4 query patterns × 5 `n` sizes ×
6 `m` sizes × 2 element types. The previous tree fell out of the bench
sweep with median 1.18× / p95 2.09× / max 2.78× slack against the per-cell
optimum; the retuned tree comes in at median 1.04× / p95 1.38× /
max 2.18×.

New branches and constants:

  - `SIMDLinearScan` is now dispatched by `Auto` in the medium-gap regime
    (`gap ∈ (4, _auto_simd_gap_max(v)]`) when `v` is `DenseVector{Int64}`
    or `DenseVector{Float64}`. `_auto_simd_gap_max` is 64 for both eltypes.
    For Float64 the dispatch consults `SearchProperties.has_nan` if
    available; otherwise no-NaN is assumed, consistent with how
    `Base.searchsortedlast` already trusts the input is sorted.
  - `BracketGallop` is preferred over `ExpFromLeft` at `gap ≥ 16` (new
    constant `_AUTO_GALLOP_GAP_MIN`). The five up-front linear probes of
    `ExpFromLeft` are guaranteed to miss once the answer is more than five
    elements past the previous-result hint, so the doubling-from-`hint`
    walk of `BracketGallop` is strictly faster at large gaps.
  - Tiered linearity probe for `InterpolationSearch`. The strict
    `_AUTO_LINEAR_REL_TOLERANCE = 1e-3` still gates the
    `_AUTO_INTERP_MIN_GAP ≤ gap < _AUTO_INTERP_LOOSE_GAP` (8 to 256) range
    — only truly uniform data passes. For `gap ≥ _AUTO_INTERP_LOOSE_GAP`
    (256), the loose `_AUTO_LINEAR_LOOSE_TOLERANCE = 5e-2` applies, which
    accepts approximately linear data (sorted random, jittered) where the
    O(√n)/n order-statistic deviation is well below 5 %. `InterpolationSearch`
    still loses on log-spaced and two-scale at any gap, and the strict tier
    catches those.

Bug fix: `_estimate_avg_gap` no longer falls back to `n ÷ m` when the
skew flag is set. The fallback caused `SIMDLinearScan` to be picked for
tightly-clustered queries (span_q ≈ 0) where `LinearScan`'s scalar walk
is 5× faster. The skew flag now serves its intended purpose as a binary
InterpolationSearch-unsuitability signal, while the actual gap value is
always the span-based estimate.

Reproducibility: the full sweep is checked in at `bench/auto_sweep.jl`
with an analysis helper at `bench/analyze.jl`. See `auto.md` for the
decision tree, the per-regime winner distribution, and how to run the
sweep locally.

### New (opt-in): BitInterpolationSearch for log-spaced Float64 data

`BitInterpolationSearch` is a variant of `InterpolationSearch` that
reinterprets a positive `DenseVector{Float64}` as `DenseVector{UInt64}`
before computing the extrapolation guess. The IEEE bit pattern is
monotonically increasing with the float value (for positive Float64) and
approximately linear in array index when the underlying data is
log-spaced (geometric). On such data the bit-domain guess can be far
better than the float-domain guess that `InterpolationSearch` would
compute.

A targeted bench sweep at `bench/bitinterp_sweep.jl` covers 9 v patterns
× 4 q patterns × 6 n sizes (up to 2²⁰) × 7 m sizes, with v patterns
specifically chosen to probe BitInterp's regime: `logspaced` (1 to 10⁶),
`logspaced_wide` (10⁻³ to 10¹⁵), `geometric_dense` (geometric spanning
10⁶), `geometric_sparse` (geometric spanning 10¹²), `power2`, `sqrt`,
`two_decade`, `jittered_log`, and `uniform` (as the negative control).

Result over 1404 cells: BitInterp wins outright in 59 cells (4.2%) and
sits within 10% of the per-cell best in 75 cells (5.3%). The wins
concentrate in `logspaced_wide` / `logspaced` / `geometric_*` /
`jittered_log` at small m (= 4) and large n (≥ 16384). Margins range
from 1.0× (tie) to 1.43× (`logspaced_wide log_grid n=2²⁰ m=4`). On
non-log-spaced data (`uniform`, `power2`, `sqrt`, `two_decade`)
BitInterp loses — the bit-pattern guess is worse than the float-domain
guess when the data isn't geometric.

**`Auto` does not pick BitInterp.** The wins are real but narrow
(small batches, very large n, true log-spacing), and adding the dispatch
overhead to Auto's hot path would penalize the much larger set of
non-log-spaced workloads. The strategy is exported as `BitInterpolationSearch`
for callers who know their data is log-spaced and want to pin it.

Constraints:
  - `DenseVector{Float64}` only; non-Float64 dense eltypes fall back to
    plain `InterpolationSearch`.
  - Requires `v[1] > 0`, `x > 0`, and both finite. Subnormal /
    non-finite Float64 bit patterns are not monotonic with float value
    under raw reinterpret, so the strategy falls back to `BinaryBracket`
    in those cases.
  - Forward ordering only.

### Cleanup: typo fix, FFE_IR unification, tolerance kwarg

  - Internal helper `bracketstrictlymontonic` renamed to
    `bracketstrictlymonotonic` (and the companion `_first` variant).
    Internal-only — no downstream impact.
  - The `FFE_IR` SIMD-equality IR literal is now generated by
    `_simd_scan_ir("i64", "eq")` instead of duplicating ~60 lines of
    inline LLVM IR. The same template produces the four `>`/`>=`
    variants for `SIMDLinearScan`, so all five SIMD primitives share a
    single source of truth.
  - `SearchProperties(v; linear_tolerance = 1e-3)` exposes the
    sampled-linearity probe's tolerance as a kwarg, matching `Guesser`'s
    `looks_linear_threshold`. Loosen (e.g. `1e-2`) to widen the regime
    where `Auto(props)` picks `InterpolationSearch`; tighten (e.g.
    `1e-4`) to be more conservative. Default unchanged at `1e-3`.

`findequal`'s docstring now explicitly documents the sentinel value
`firstindex(v) - 1` and its behaviour on OffsetArrays.

### Compatibility

  - **Julia compat**: unchanged from 1.x — `julia = "1.10"`.
  - **Downstream PRs**: SciML packages using the removed names need
    companion PRs. The first one
    [SciML/DataInterpolations.jl#529](https://github.com/SciML/DataInterpolations.jl/pull/529)
    is the migration template: drop the legacy imports, route the
    `Integer`-hint path through `searchsortedfirst(BracketGallop(), …)`
    and the `Guesser` path through `searchsortedfirst(GuesserHint(g), …)`.

### Test coverage

47100 tests pass across the strategy dispatch, the batched API, the
`Auto` heuristic on a regime sweep, `SIMDLinearScan` randomized fuzz
(10000 Int64 + 10000 Float64 cases against `Base`), edge cases (empty,
single-element, duplicates, out-of-range hints, x outside the vector
range), fallback paths (Int32, Float32, String, no-hint, reverse
order), and `SearchProperties` cache correctness (output equivalence
against the un-cached path, `isbits` guarantee, behaviour under lying
cache).

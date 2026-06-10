# Search strategies

The strategies form the parameter space of the sorted-search API. Two
ways to select a strategy:

  - **v3 preferred:** pass a [`StrategyKind`](@ref FindFirstFunctions.StrategyKind)
    enum value (e.g. `KIND_BRACKET_GALLOP`) as the first argument to
    [`search_last`](@ref FindFirstFunctions.search_last) /
    [`search_first`](@ref FindFirstFunctions.search_first). One enum
    value per singleton strategy; runtime `if/elseif` dispatch into the
    matching kernel; ~0 ns of overhead in hot loops; the inferred return
    type is concrete regardless of which kind is picked at runtime.
  - **v2 back-compat:** pass a singleton strategy struct (e.g.
    `BracketGallop()`) to `Base.searchsortedlast` / `Base.searchsortedfirst`.
    Each method is a one-line shim that forwards to `search_last(KIND_X, ...)`.
    Scheduled for removal in v4 — migrate to `search_last` /
    `search_first` for new code.

The stateful strategies — [`Auto`](@ref FindFirstFunctions.Auto) and
[`GuesserHint`](@ref FindFirstFunctions.GuesserHint) — carry per-instance
data and so cannot be expressed as singleton enum tags. They dispatch
via their own multimethods (and via the back-compat `Base.searchsortedlast(::S, ...)`
shim).

```@docs
FindFirstFunctions.SearchStrategy
FindFirstFunctions.StrategyKind
FindFirstFunctions.search_last
FindFirstFunctions.search_first
FindFirstFunctions.strategy_kind
```

## Kind ↔ strategy mapping

| Enum tag | Strategy struct | Kernel function |
|---|---|---|
| `KIND_BINARY_BRACKET` | `BinaryBracket` | `_kernel_last_binary_bracket` / `_kernel_first_binary_bracket` |
| `KIND_LINEAR_SCAN` | `LinearScan` | `_kernel_last_linear_scan` / `_kernel_first_linear_scan` |
| `KIND_SIMD_LINEAR_SCAN` | `SIMDLinearScan` | `_kernel_last_simd_linear_scan` / `_kernel_first_simd_linear_scan` |
| `KIND_BRACKET_GALLOP` | `BracketGallop` | `_kernel_last_bracket_gallop` / `_kernel_first_bracket_gallop` |
| `KIND_EXP_FROM_LEFT` | `ExpFromLeft` | `_kernel_last_exp_from_left` / `_kernel_first_exp_from_left` |
| `KIND_INTERPOLATION_SEARCH` | `InterpolationSearch` | `_kernel_last_interpolation_search` / `_kernel_first_interpolation_search` |
| `KIND_BIT_INTERPOLATION_SEARCH` | `BitInterpolationSearch` | `_kernel_last_bit_interpolation_search` / `_kernel_first_bit_interpolation_search` |
| `KIND_UNIFORM_STEP` | `UniformStep` | `_kernel_last_uniform_step` / `_kernel_first_uniform_step` |
| `KIND_BISECT_THEN_SIMD` | `BisectThenSIMD` | (positional dispatch falls back to BinaryBracket; equality dispatch goes through `findfirstsortedequal`) |

Stateful strategies that do **not** have an enum tag and stay on the
multimethod path:

  - [`Auto`](@ref FindFirstFunctions.Auto): carries a `StrategyKind` field
    plus a [`SearchProperties`](@ref FindFirstFunctions.SearchProperties)
    cache. `Auto`'s `search_last` is a one-line forward to the stored
    kind; the batched dispatch re-resolves the kind from
    `(v, queries)` because the gap heuristic needs the queries.
  - [`GuesserHint`](@ref FindFirstFunctions.GuesserHint): carries a
    [`Guesser`](@ref FindFirstFunctions.Guesser) (with its `idx_prev::Ref{Int}`
    and `linear_lookup::Bool`). Dispatches via its own
    `search_last(::GuesserHint, ...)` / `search_first(::GuesserHint, ...)`
    methods.

## When to pick which

For most callers the answer is: pass [`Auto`](@ref FindFirstFunctions.Auto)
(the default in the batched API) and let it choose. The table below is for
callers who already know their access pattern and want to pin a strategy.

| Strategy | Best when | Cost when hint hits | Cost worst case | Uses hint? |
|---|---|---|---|---|
| [`LinearScan`](@ref FindFirstFunctions.LinearScan) | answer is within a handful of slots of the hint | O(1) | O(n) | yes |
| [`SIMDLinearScan`](@ref FindFirstFunctions.SIMDLinearScan) | `DenseVector{Int64}` or `DenseVector{Float64}`, forward walk past the hint | O(1) | O(n/8) | yes |
| [`BracketGallop`](@ref FindFirstFunctions.BracketGallop) | answer may be either side of the hint, distance unknown | O(1) | ~2 log₂ n | yes |
| [`ExpFromLeft`](@ref FindFirstFunctions.ExpFromLeft) | sorted batch — hint is `prev_result`, answer is monotonically ≥ hint | O(1) | O(log n) | yes (as lower bound) |
| [`InterpolationSearch`](@ref FindFirstFunctions.InterpolationSearch) | `v` is uniformly spaced and numeric | O(1) | O(log n) | no |
| [`BitInterpolationSearch`](@ref FindFirstFunctions.BitInterpolationSearch) | `DenseVector{Float64}` and log-spaced (geometric) — opt-in, `Auto` does not pick | O(1) | O(log n) | no |
| [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket) | no hint available, or fallback | O(log n) | O(log n) | no |
| [`UniformStep`](@ref FindFirstFunctions.UniformStep) | `v isa AbstractRange` (or known-uniformly-spaced) | O(1) | O(1) | no |
| [`GuesserHint`](@ref FindFirstFunctions.GuesserHint) | repeated correlated lookups against the same `v` | O(1) | ~2 log₂ n | self-provided |
| [`Auto`](@ref FindFirstFunctions.Auto) | unknown access pattern | varies | varies | yes if supplied |

All hint-consuming strategies fall back to `BinaryBracket` when no hint is
supplied or when the hint is out of range. `InterpolationSearch` additionally
falls back to `BinaryBracket` for non-numeric element types.

## Migrating from v2 (`Base.searchsortedlast(::S, ...)`) to v3 (`search_last(KIND_X, ...)`)

The v2 API is preserved as a back-compat shim. To migrate to the v3
preferred form, change each call site as follows:

```julia
# v2 (still works, shim forwards to v3)
searchsortedlast(BracketGallop(), v, x, hint)
searchsortedfirst(InterpolationSearch(), v, x)

# v3 (preferred)
search_last(KIND_BRACKET_GALLOP, v, x, hint)
search_first(KIND_INTERPOLATION_SEARCH, v, x)
```

Stateful strategies (`Auto`, `GuesserHint`) have both forms:

```julia
# v2 form (still works)
searchsortedlast(Auto(v), v, x, hint)
searchsortedfirst(GuesserHint(g), v, x)

# v3 form (preferred)
search_last(Auto(v), v, x, hint)
search_first(GuesserHint(g), v, x)
```

The migration is mechanical: rename `searchsortedlast` → `search_last`,
`searchsortedfirst` → `search_first`, and wrap singleton struct
strategies with their `KIND_X` tag (no rename needed for stateful
strategies).

The v2 shims will be removed in **v4** (no scheduled date — long enough
for downstream packages like DataInterpolations.jl, ModelingToolkit, and
NonlinearSolve to migrate).

## Reference

```@docs
FindFirstFunctions.LinearScan
FindFirstFunctions.SIMDLinearScan
FindFirstFunctions.BracketGallop
FindFirstFunctions.ExpFromLeft
FindFirstFunctions.InterpolationSearch
FindFirstFunctions.BitInterpolationSearch
FindFirstFunctions.BinaryBracket
FindFirstFunctions.BisectThenSIMD
FindFirstFunctions.UniformStep
FindFirstFunctions.Auto
FindFirstFunctions.SearchProperties
```

## Equality search through the strategy framework

Strategies answer positional questions ("where would `x` insert?"). Equality
asks a different question ("is `x` at exactly which index?"). The
[`findequal`](@ref FindFirstFunctions.findequal) wrapper builds the latter
on top of the former: every strategy gets an equality variant for free.

```@docs
FindFirstFunctions.findequal
```

The sentinel for "not found" is `firstindex(v) - 1` (`= 0` for 1-based
vectors). Type-stable `Int` return, no `Union` with `Nothing`. Callers can
test for absence with `i < firstindex(v)`.

`findequal` routes most strategies through `search_first + post-check`
generically, so `findequal(BracketGallop(), v, x, hint)`,
`findequal(SIMDLinearScan(), v, x, hint)`,
`findequal(GuesserHint(g), v, x)`, `findequal(KIND_BRACKET_GALLOP, v, x, hint)`,
etc. all just work.

The [`BisectThenSIMD`](@ref FindFirstFunctions.BisectThenSIMD) strategy
short-circuits the post-check path on `DenseVector{Int64}` by dispatching
into [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal)
directly — same custom LLVM IR scan, exposed through the strategy framework.

`GuesserHint` is documented on the [Guessers](@ref) page.

## Notes on individual strategies

### LinearScan

Walks `±1` from the hint until the answer is bracketed. Cheapest possible
search when the hint is right next to the answer — two comparisons. The only
strategy whose worst case is O(n), so it should only be picked when the
caller has strong evidence that the hint is close.

For `length(v) ≤ 16`, `LinearScan` is faster than `BracketGallop` even from a
bad hint because the bracket bookkeeping costs more than a worst-case walk
across a vector that short. `Auto`'s resolution rule picks `KIND_LINEAR_SCAN`
below that threshold.

### SIMDLinearScan

Same algorithm as `LinearScan`, with the **forward** walk past the hint
lowered to 8-wide SIMD chunks via custom LLVM IR. The backward walk (when
the hint is past the answer) uses the scalar `LinearScan` path — the SIMD
primitive is only defined in the forward direction.

Specialized for `DenseVector{Int64}` and `DenseVector{Float64}`. Any other
element type falls back to the scalar `LinearScan` walk. The dispatch is
*static* — there's no runtime type test on a hot path.

Caveats:

  - **Element types**: `Int64` and `Float64` only.
  - **NaN**: a `NaN` element in a `Float64` vector compares as `false` —
    the SIMD scan silently skips it. Sorted `Float64` vectors containing
    `NaN` aren't well-defined under any total order.
  - **Order**: `Forward` and `Reverse` only.
  - **No hint**: falls back to [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket).
  - **Auto does not pick this strategy** by default in the per-query path.
    The batched dispatch picks it inside a gap window where the SIMD chunk
    pays for itself.

### BitInterpolationSearch

`InterpolationSearch` with the extrapolation guess computed on the IEEE
bit pattern of `v` rather than the float values themselves. Wins on
log-spaced (geometric) data — sometimes O(1) versus O(log n) refinement
cost.

**Opt-in only.** `Auto` does not pick `BitInterpolationSearch`.

Falls back to plain `InterpolationSearch` on non-Float64 dense eltypes,
and to `BinaryBracket` for non-positive or non-finite Float64 data.

### BracketGallop

Galloping search around the hint: expand `[lo, hi]` outward by doubling steps
until `x` is bracketed, then binary-search inside `[lo, hi]`. Direction is
inferred from `v[hint]` vs. `x`, so the hint can be either above or below the
answer. Worst case is ~2 log₂ n — about twice plain binary search — and it
matches O(1) when the hint is close.

This is the workhorse hinted strategy and the natural choice for
`get_idx`-style callers where the hint is a cached previous result.

### ExpFromLeft

Exponential search forward from a hint interpreted as a *lower bound*. The
algorithm probes `v[lo], v[lo+1], …, v[lo+4]` linearly, then `v[lo+8],
v[lo+16], …` exponentially, then binary-searches inside the final bracket.

Used by `Auto`'s batched dispatch when the queries are sorted: each call
passes `hint = previous_result`, which by sortedness satisfies the "answer ≥
hint" precondition.

### InterpolationSearch

Computes a guess via linear extrapolation between `v[lo]` and `v[hi]`, then
refines with a bounded binary search around that guess. On uniformly-spaced
numeric data the first guess is the right answer — O(1) per query
independent of `n`.

Two restrictions:

  - **Numeric eltype**: non-numeric eltypes fall back to `BinaryBracket`.
  - **Forward ordering only**: non-`Forward` orderings fall back to
    `BinaryBracket`.

The hint is ignored — the guess is computed fresh from the endpoints.

### BinaryBracket

Plain `Base.searchsortedlast` / `Base.searchsortedfirst`. Provided as a
strategy so callers can opt out of hint-based behaviour explicitly, and so
other strategies have a well-defined name to fall back to. Ignores any
hint.

### Auto

See [Auto: heuristics and benchmarks](@ref) for the full decision tree and
the benchmark sweep that produced its crossover constants.

In v3, `Auto` carries a stored `StrategyKind` plus a `SearchProperties`
cache:

  - `Auto()` defaults to `KIND_BINARY_BRACKET`. Safe but no faster than
    plain `Base.searchsortedlast`.
  - `Auto(v)` resolves the kind from `length(v)` and `SearchProperties(v)`.
    Picks `KIND_UNIFORM_STEP` for `AbstractRange` / detected-uniform
    vectors, `KIND_LINEAR_SCAN` for short vectors, `KIND_BRACKET_GALLOP`
    otherwise.
  - `Auto(v, props)` is the same with a pre-computed `props` cache.

The per-query `search_last(::Auto, v, x, hint)` is a one-line forward to
`search_last(s.kind, v, x, hint)`. The batched
`searchsortedlast!(out, v, queries; strategy = Auto())` re-resolves the
kind from `(v, queries)` to consult the gap heuristic.

## Equality routines

The package exposes two `Union{Int, Nothing}`-returning equality routines —
[`findfirstequal`](@ref FindFirstFunctions.findfirstequal) (unsorted SIMD
scan) and [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal)
(sorted bisect-then-SIMD scan). See the [Equality search](@ref Equality-search) page for
the full documentation.

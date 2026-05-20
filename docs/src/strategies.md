# Search strategies

The strategies form the parameter space of the sorted-search API. Each one
subtypes [`SearchStrategy`](@ref FindFirstFunctions.SearchStrategy) and is
selected as the first positional argument of `searchsortedfirst` /
`searchsortedlast`.

```@docs
FindFirstFunctions.SearchStrategy
```

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
| [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket) | no hint available, or fallback | O(log n) | O(log n) | no |
| [`GuesserHint`](@ref FindFirstFunctions.GuesserHint) | repeated correlated lookups against the same `v` | O(1) | ~2 log₂ n | self-provided |
| [`Auto`](@ref FindFirstFunctions.Auto) | unknown access pattern | varies | varies | yes if supplied |

All hint-consuming strategies fall back to `BinaryBracket` when no hint is
supplied or when the hint is out of range. `InterpolationSearch` additionally
falls back to `BinaryBracket` for non-numeric element types.

## Reference

```@docs
FindFirstFunctions.LinearScan
FindFirstFunctions.SIMDLinearScan
FindFirstFunctions.BracketGallop
FindFirstFunctions.ExpFromLeft
FindFirstFunctions.InterpolationSearch
FindFirstFunctions.BinaryBracket
FindFirstFunctions.BisectThenSIMD
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

`findequal` routes most strategies through `searchsortedfirst + post-check`
generically, so `findequal(BracketGallop(), v, x, hint)`,
`findequal(SIMDLinearScan(), v, x, hint)`,
`findequal(GuesserHint(g), v, x)`, etc. all just work.

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
across a vector that short. `Auto`'s per-query path picks `LinearScan` below
that threshold.

### SIMDLinearScan

Same algorithm as `LinearScan`, with the **forward** walk past the hint
lowered to 8-wide SIMD chunks via custom LLVM IR. The backward walk (when
the hint is past the answer) uses the scalar `LinearScan` path — the SIMD
primitive is only defined in the forward direction.

Specialized for `DenseVector{Int64}` and `DenseVector{Float64}`. Any other
element type falls back to the scalar `LinearScan` walk (this includes
`Int32`, `UInt64`, `Float32`, `Date`, `String`, and user-defined numeric
types). The dispatch is *static* — there's no runtime type test on a hot
path — so the fallback costs nothing per-call when picked at compile time.

Caveats:

  - **Element types**: `Int64` and `Float64` only. Anything else uses
    scalar `LinearScan`. This is a hard restriction of the LLVM IR: the
    vector load uses `<8 x i64>` / `<8 x double>` with 8-byte stride, and
    the broadcast and compare are typed accordingly.
  - **NaN**: a `NaN` element in a `Float64` vector compares as `false`
    under both `fcmp ogt` and `fcmp oge`, so a NaN in `v` is silently
    skipped by the SIMD scan. Sorted `Float64` vectors containing `NaN`
    aren't well-defined under any total order anyway — same caveat
    applies to plain `Base.searchsortedlast` on such vectors.
  - **Forward order only**: non-`Forward` orderings fall back to scalar
    `LinearScan`. The IR is hard-coded to the `Forward` comparison
    polarity.
  - **No hint**: falls back to [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket).
    Without a hint there's no direction information for the forward scan.
  - **Auto does not pick this strategy.** `SIMDLinearScan` is opt-in. It
    isn't part of the `Auto` decision tree because the regime where it
    strictly beats `LinearScan` (long forward walks on `Int64`/`Float64`)
    overlaps with the regime where `Auto` already prefers
    [`BracketGallop`](@ref FindFirstFunctions.BracketGallop) or
    [`ExpFromLeft`](@ref FindFirstFunctions.ExpFromLeft). Pin it
    explicitly when you have a workload that wants a long linear forward
    scan and you know the element type.

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
hint" precondition. When the precondition is violated (the caller passes a
hint past the answer), `ExpFromLeft` falls back to a full
`searchsortedfirst` / `searchsortedlast` — slow but correct.

### InterpolationSearch

Computes a guess via linear extrapolation between `v[lo]` and `v[hi]`, then
refines with a bounded binary search around that guess. On uniformly-spaced
numeric data the first guess is the right answer — O(1) per query
independent of `n`. On irregular data the guess is bad and the binary search
inside the (full) bracket falls back to O(log n).

Two restrictions:

  - **Numeric eltype**: requires `x - v[i]` to be well-defined and produce a
    number whose ratio with `v[hi] - v[lo]` makes sense. Non-numeric eltypes
    fall back to `BinaryBracket`.
  - **Forward ordering only**: the linear-extrapolation formula assumes
    `v[lo] ≤ v[hi]`. Non-`Forward` orderings fall back to `BinaryBracket`.

The hint is ignored — the guess is computed fresh from the endpoints.

### BinaryBracket

Plain `Base.searchsortedlast` / `Base.searchsortedfirst`. Provided as a
strategy so that callers can opt out of hint-based behaviour explicitly, and
so that other strategies have a well-defined name to fall back to. Ignores
any hint that is supplied.

### Auto

See [Auto: heuristics and benchmarks](@ref) for the full decision tree and
the benchmark sweep that produced its crossover constants.

## Equality search

Separate from the sorted-search strategy dispatch, the package exposes two
specialized equality routines for `Int64` vectors. These find an exact match
(returning `nothing` if no match exists), so they are not strategies —
their return semantics differ from `searchsortedfirst`/`searchsortedlast`.

```@docs
FindFirstFunctions.findfirstequal
FindFirstFunctions.findfirstsortedequal
```

`findfirstequal` does an unsorted SIMD scan (~8× faster than scalar
`findfirst(==(x), v)` for `Int64`). `findfirstsortedequal` does a branchless
binary bisection down to a small basecase, then dispatches into the same
SIMD scan. Both are restricted to `DenseVector{Int64}`; for other element
types `findfirstequal` falls back to `findfirst(==(x), v)`.

For sorted equality search through the strategy framework, prefer
[`findequal`](@ref FindFirstFunctions.findequal) (see the previous section)
— it gives a type-stable `Int` return with a sentinel for "not found",
participates in the strategy dispatch, and short-circuits to
`findfirstsortedequal`'s SIMD algorithm via the
[`BisectThenSIMD`](@ref FindFirstFunctions.BisectThenSIMD) strategy when
the eltype is `Int64`. `findfirstsortedequal` and `findfirstequal` remain
as backward-compatible dedicated names.

The `findfirstequal` unsorted variant is intentionally outside the strategy
framework: positional strategies (binary search, galloping, interpolation)
all require a sorted input, while `findfirstequal` operates on arbitrary
vectors.

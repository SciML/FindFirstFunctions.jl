# Interface and extension rules

This page documents the public sorted-search API surface and the contract a
custom [`SearchStrategy`](@ref FindFirstFunctions.SearchStrategy) subtype
must satisfy.

## Public API surface

In 2.x the sorted-search public API is a single pair of generic functions
overloaded on a strategy as the first positional argument:

```julia
searchsortedfirst(strategy, v, x[, hint]; order = Base.Order.Forward)
searchsortedlast(strategy, v, x[, hint]; order = Base.Order.Forward)
```

and the in-place batched variants:

```julia
searchsortedfirst!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)
searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)
```

The strategy types live in the `FindFirstFunctions` module; the
`searchsortedfirst`/`searchsortedlast` names are extended from `Base` so they
compose with existing `Base.Order` orderings.

```@docs
FindFirstFunctions.searchsortedfirst!
FindFirstFunctions.searchsortedlast!
```

## Rules of the interface

  1. **Hint is optional and is an `Integer`.** When supplied it must be a
     valid index into `v` (`firstindex(v) ≤ hint ≤ lastindex(v)`). An
     out-of-range hint is silently treated as "no hint" by every built-in
     strategy. A strategy is allowed to ignore the hint entirely
     ([`InterpolationSearch`](@ref FindFirstFunctions.InterpolationSearch),
     [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket)).
  2. **Strategies are singletons or wrappers.** `LinearScan`, `BracketGallop`,
     `ExpFromLeft`, `InterpolationSearch`, `BinaryBracket`, and `Auto` are
     zero-field singletons.
     [`GuesserHint`](@ref FindFirstFunctions.GuesserHint) is a thin wrapper
     around a [`Guesser`](@ref FindFirstFunctions.Guesser). New strategies
     should follow the same pattern: parameters that change *behaviour*
     belong on the type; parameters that change *cost only* should be tuned
     internally.
  3. **No mutation of `v` or `x`.** A strategy never writes to the searched
     vector or to the query. The only state that may change across calls is
     hint state carried by the strategy itself (e.g. `GuesserHint` updates
     `guesser.idx_prev`).
  4. **Order is honored.** Every strategy accepts an `order::Base.Order.Ordering`
     keyword and returns indices consistent with `Base.searchsortedfirst` /
     `Base.searchsortedlast` under that ordering. Strategies that are only
     efficient under `Forward` ordering (e.g. `InterpolationSearch`,
     `ExpFromLeft`) fall back to `BinaryBracket` for non-`Forward` orderings.
  5. **`AbstractRange` is already O(1).** `Base.searchsortedfirst(r::AbstractRange, x)`
     has a closed-form implementation. Strategies do not need range fast
     paths — the `BinaryBracket` fallback already calls into Base's
     range-aware method.

## Anatomy of a strategy

A built-in strategy provides up to four methods on each of
`Base.searchsortedfirst` / `Base.searchsortedlast`:

```julia
# Required: the hinted form (the strategy's reason for existing).
Base.searchsortedlast(::MyStrategy, v, x, hint::Integer; order) = ...
Base.searchsortedfirst(::MyStrategy, v, x, hint::Integer; order) = ...

# Required: the unhinted form. Most strategies just fall back to BinaryBracket.
Base.searchsortedlast(::MyStrategy, v, x; order) = searchsortedlast(BinaryBracket(), v, x; order)
Base.searchsortedfirst(::MyStrategy, v, x; order) = searchsortedfirst(BinaryBracket(), v, x; order)
```

If your strategy ignores the hint, define just the unhinted form and have the
hinted form delegate to it (see `BinaryBracket` and `InterpolationSearch` in
the source).

## How to add a new strategy

Two steps.

### 1. Define the strategy type

Pick a name that describes the *algorithm*, not the use case. Make it a
subtype of [`SearchStrategy`](@ref FindFirstFunctions.SearchStrategy):

```julia
"""
    MyStrategy <: FindFirstFunctions.SearchStrategy

One sentence on what it does. One sentence on when it wins. One sentence on
when it falls back.
"""
struct MyStrategy <: FindFirstFunctions.SearchStrategy end
```

If your strategy carries state (like `GuesserHint`), make it a parametric
struct:

```julia
struct MyStrategy{S} <: FindFirstFunctions.SearchStrategy
    state::S
end
```

### 2. Implement the dispatch methods

At minimum, the hinted forms:

```julia
function Base.searchsortedlast(
        ::MyStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    # Algorithm body. Must return the same index that
    # `Base.searchsortedlast(v, x, order)` would.
    ...
end

function Base.searchsortedfirst(
        ::MyStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    ...
end
```

Plus unhinted forms (typically fallbacks):

```julia
Base.searchsortedlast(s::MyStrategy, v::AbstractVector, x; order = Base.Order.Forward) =
    searchsortedlast(FindFirstFunctions.BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(s::MyStrategy, v::AbstractVector, x; order = Base.Order.Forward) =
    searchsortedfirst(FindFirstFunctions.BinaryBracket(), v, x; order = order)
```

### Correctness check

Every strategy must return the same answer as plain `Base.searchsortedlast` /
`Base.searchsortedfirst` for every `(v, x[, hint])` triple. Test with random
inputs against `Base`:

```julia
using Test, Random
Random.seed!(0)
for trial in 1:10_000
    v = sort!(randn(rand(1:1000)))
    x = randn()
    hint = rand(1:length(v))
    @test searchsortedlast(MyStrategy(), v, x, hint) == searchsortedlast(v, x)
    @test searchsortedfirst(MyStrategy(), v, x, hint) == searchsortedfirst(v, x)
end
```

### Hooking into `Auto`

`Auto`'s decision tree lives in `_auto_pick` (per-query) and
`_searchsortedlast_batched!(_, _, _, ::Auto, _)` /
`_searchsortedfirst_batched!(_, _, _, ::Auto, _)` (batched). It is **not
extensible from outside** — new strategies do not register themselves with
`Auto` automatically. If you believe `Auto` should pick your strategy in
some regime, open an issue with benchmark numbers across the regime grid in
[Auto: heuristics and benchmarks](@ref).

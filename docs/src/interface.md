# Interface and extension rules

This page documents the public sorted-search API surface and the contract a
custom [`SearchStrategy`](@ref FindFirstFunctions.SearchStrategy) subtype
must satisfy.

## Public API surface

The sorted-search public API is the pair of FFF-owned generic functions
dispatched on a strategy as the first positional argument:

```julia
searchsorted_first(strategy, v, x[, hint]; order = Base.Order.Forward)
searchsorted_last(strategy, v, x[, hint]; order = Base.Order.Forward)
```

`strategy` is a [`StrategyKind`](@ref FindFirstFunctions.StrategyKind) enum
value (`KIND_BRACKET_GALLOP`, …), a singleton strategy struct
(`BracketGallop()`, … — forwards through
[`strategy_kind`](@ref FindFirstFunctions.strategy_kind) and constant-folds
for a literal argument), or a stateful strategy (`Auto`, `GuesserHint`).

The in-place batched variants:

```julia
searchsortedfirst!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)
searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)
```

FindFirstFunctions does not extend `Base.searchsortedfirst` /
`Base.searchsortedlast` — all strategy dispatch happens through the
FFF-owned names above, which compose with the same `Base.Order` orderings.

```@docs
FindFirstFunctions.searchsortedfirst!
FindFirstFunctions.searchsortedlast!
FindFirstFunctions.searchsortedrange
```

## Rules of the interface

  1. **Hint is optional and is an `Integer`.** When supplied it must be a
     valid index into `v` (`firstindex(v) ≤ hint ≤ lastindex(v)`). An
     out-of-range hint is silently treated as "no hint" by every built-in
     strategy. A strategy is allowed to ignore the hint entirely
     ([`InterpolationSearch`](@ref FindFirstFunctions.InterpolationSearch),
     [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket)).
  2. **Strategies are singletons or wrappers.** `LinearScan`, `BracketGallop`,
     `ExpFromLeft`, `InterpolationSearch`, and `BinaryBracket` are
     zero-field singletons mapped to their `StrategyKind` tag by
     `strategy_kind`. [`Auto`](@ref FindFirstFunctions.Auto) carries a
     resolved kind plus a `SearchProperties` payload;
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

A built-in singleton strategy consists of a `StrategyKind` enum value, a
pair of kernel functions (`_kernel_last_<name>` / `_kernel_first_<name>` in
`src/kernels.jl`), and branches in the four dispatch switches in
`src/kinds.jl` (hinted/unhinted × last/first). The "no hint" branch of a
hint-using strategy falls back to `BinaryBracket`; the hinted branch of a
hint-ignoring strategy discards the hint.

A custom strategy defined outside the package cannot add an enum value
(the enum is closed), so it provides its own `searchsorted_last` / `searchsorted_first`
methods instead — these are more specific than the generic
`SearchStrategy` fallback and take precedence:

```julia
# Required: the hinted form (the strategy's reason for existing).
FindFirstFunctions.searchsorted_last(::MyStrategy, v, x, hint::Integer; order) = ...
FindFirstFunctions.searchsorted_first(::MyStrategy, v, x, hint::Integer; order) = ...

# Required: the unhinted form. Most strategies just fall back to BinaryBracket.
FindFirstFunctions.searchsorted_last(::MyStrategy, v, x; order) =
    FindFirstFunctions.searchsorted_last(FindFirstFunctions.KIND_BINARY_BRACKET, v, x; order)
FindFirstFunctions.searchsorted_first(::MyStrategy, v, x; order) =
    FindFirstFunctions.searchsorted_first(FindFirstFunctions.KIND_BINARY_BRACKET, v, x; order)
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
function FindFirstFunctions.searchsorted_last(
        ::MyStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    # Algorithm body. Must return the same index that
    # `Base.searchsortedlast(v, x, order)` would.
    ...
end

function FindFirstFunctions.searchsorted_first(
        ::MyStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    ...
end
```

Plus unhinted forms (typically fallbacks):

```julia
FindFirstFunctions.searchsorted_last(s::MyStrategy, v::AbstractVector, x; order = Base.Order.Forward) =
    FindFirstFunctions.searchsorted_last(FindFirstFunctions.KIND_BINARY_BRACKET, v, x; order = order)
FindFirstFunctions.searchsorted_first(s::MyStrategy, v::AbstractVector, x; order = Base.Order.Forward) =
    FindFirstFunctions.searchsorted_first(FindFirstFunctions.KIND_BINARY_BRACKET, v, x; order = order)
```

When a strategy contributes to the package itself, add a `StrategyKind`
enum value, the kernel pair, the four dispatch-switch branches, and a
`strategy_kind` method instead — see `src/kinds.jl` and
`src/strategy_kind.jl`.

### Correctness check

Every strategy must return the same answer as plain `Base.searchsortedlast` /
`Base.searchsortedfirst` for every `(v, x[, hint])` triple. Test with random
inputs against `Base`:

```julia
using Test, Random
using FindFirstFunctions: searchsorted_last, searchsorted_first
Random.seed!(0)
for trial in 1:10_000
    v = sort!(randn(rand(1:1000)))
    x = randn()
    hint = rand(1:length(v))
    @test searchsorted_last(MyStrategy(), v, x, hint) == searchsortedlast(v, x)
    @test searchsorted_first(MyStrategy(), v, x, hint) == searchsortedfirst(v, x)
end
```

### Hooking into `Auto`

`Auto`'s decision tree lives in `_auto_resolve_kind` (construction-time)
and `_auto_batched_kind` (batched). It is **not extensible from outside** —
new strategies do not register themselves with `Auto` automatically. If you
believe `Auto` should pick your strategy in some regime, open an issue with
benchmark numbers across the regime grid in
[Auto: heuristics and benchmarks](@ref).

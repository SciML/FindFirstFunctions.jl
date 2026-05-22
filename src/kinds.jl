# Enum-tagged dispatch for singleton search strategies.
#
# Each value of `StrategyKind` names one of the singleton, zero-state
# strategies. The pair `search_last` / `search_first` is the single public
# entry point: a runtime-tag dispatcher that branches on the enum and
# inlines into the matching kernel function (defined in `kernels.jl`).
#
# The runtime-branch bench (DataInterpolations.jl PR #531) confirmed that
# an `if/elseif/...` over a `StrategyKind` value is ~0 ns overhead in hot
# loops because the branch is well-predicted (or eliminated by constant
# propagation when the kind is known at the call site), the kernel bodies
# inline, and the return path stays type-stable — none of the Union-return
# pathology that the old type-parameter dispatch over `SearchStrategy`
# subtypes suffered from when the chosen strategy depended on runtime data.
#
# Stateful strategies (`GuesserHint(::Guesser)`) do *not* live in the enum.
# They carry per-instance data, so a singleton tag would lose information.
# Instead they dispatch directly via their wrapper struct
# (`search_last(::GuesserHint, ...)`).

"""
    StrategyKind

Enum tag identifying a singleton search strategy. Use values of this
enum as the first positional argument to [`search_last`](@ref) and
[`search_first`](@ref):

```julia
search_last(KIND_BRACKET_GALLOP, v, x, hint)
```

Each tag corresponds to one of the singleton strategy types
(e.g. `KIND_BRACKET_GALLOP` ↔ `BracketGallop`). Stateful strategies
(`GuesserHint`) do not have an enum tag — they dispatch through their
wrapper struct directly.

The enum is stored as `UInt8` so passing it through to dispatcher
functions costs the same as a `Bool` and does not enlarge any struct
that carries it.
"""
@enum StrategyKind::UInt8 begin
    KIND_BINARY_BRACKET
    KIND_LINEAR_SCAN
    KIND_SIMD_LINEAR_SCAN
    KIND_BRACKET_GALLOP
    KIND_EXP_FROM_LEFT
    KIND_INTERPOLATION_SEARCH
    KIND_BIT_INTERPOLATION_SEARCH
    KIND_UNIFORM_STEP
    KIND_BISECT_THEN_SIMD
end

"""
    search_last(kind::StrategyKind, v, x[, hint]; order = Base.Order.Forward)
    search_last(s, v, x[, hint]; order = Base.Order.Forward)

FFF-owned positional search for the largest index `i` with `v[i] ≤ x`
under `order` (or `v[i] ≥ x` under `Base.Order.Reverse`). The polarity
matches `Base.searchsortedlast`.

When the first argument is a [`StrategyKind`](@ref) value the call
dispatches via a runtime `if/elseif` branch on the enum into the matching
kernel. When the first argument is a stateful strategy wrapper (`Auto`,
`GuesserHint`) the call dispatches via multimethod into that wrapper's
own `search_last` method.

This is the preferred entry point for new code. The legacy
`Base.searchsortedlast(::SearchStrategy, ...)` methods still work for
back-compat but are deprecated and emit a depwarn on first use.
"""
@inline function search_last(
        kind::StrategyKind, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _search_last_nohint(kind, v, x, order)
end

@inline function search_last(
        kind::StrategyKind, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _search_last_hinted(kind, v, x, hint, order)
end

"""
    search_first(kind::StrategyKind, v, x[, hint]; order = Base.Order.Forward)
    search_first(s, v, x[, hint]; order = Base.Order.Forward)

FFF-owned positional search for the smallest index `i` with `v[i] ≥ x`
under `order` (or `v[i] ≤ x` under `Base.Order.Reverse`). See
[`search_last`](@ref) for the dispatch story.
"""
@inline function search_first(
        kind::StrategyKind, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _search_first_nohint(kind, v, x, order)
end

@inline function search_first(
        kind::StrategyKind, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _search_first_hinted(kind, v, x, hint, order)
end

# ---------------------------------------------------------------------------
# The dispatch switches. One per (polarity, hint-presence) pair. Each one
# is a single `if/elseif/.../end` over the enum value — the branch is
# well-predicted at runtime and the body inlines.
#
# The kernel-function names follow a consistent scheme:
#   `_kernel_last_<strategy>` / `_kernel_first_<strategy>`
# The "no hint" entry points for hint-using strategies fall back to
# BinaryBracket internally (the existing semantics), and the hinted
# entry points for hint-ignoring strategies (BinaryBracket, BisectThenSIMD)
# discard the hint.
# ---------------------------------------------------------------------------

@inline function _search_last_hinted(
        kind::StrategyKind, v::AbstractVector, x, hint::Integer,
        order::Base.Order.Ordering,
    )
    if kind === KIND_BINARY_BRACKET
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_LINEAR_SCAN
        return _kernel_last_linear_scan(v, x, hint, order)
    elseif kind === KIND_SIMD_LINEAR_SCAN
        return _kernel_last_simd_linear_scan(v, x, hint, order)
    elseif kind === KIND_BRACKET_GALLOP
        return _kernel_last_bracket_gallop(v, x, hint, order)
    elseif kind === KIND_EXP_FROM_LEFT
        return _kernel_last_exp_from_left(v, x, hint, order)
    elseif kind === KIND_INTERPOLATION_SEARCH
        return _kernel_last_interpolation_search(v, x, order)
    elseif kind === KIND_BIT_INTERPOLATION_SEARCH
        return _kernel_last_bit_interpolation_search(v, x, order)
    elseif kind === KIND_UNIFORM_STEP
        return _kernel_last_uniform_step(v, x, order)
    else
        # KIND_BISECT_THEN_SIMD — equality-search strategy; positional
        # dispatch falls back to BinaryBracket.
        return _kernel_last_binary_bracket(v, x, order)
    end
end

@inline function _search_last_nohint(
        kind::StrategyKind, v::AbstractVector, x,
        order::Base.Order.Ordering,
    )
    if kind === KIND_BINARY_BRACKET
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_LINEAR_SCAN
        # No hint → BinaryBracket fallback.
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_SIMD_LINEAR_SCAN
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_BRACKET_GALLOP
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_EXP_FROM_LEFT
        return _kernel_last_binary_bracket(v, x, order)
    elseif kind === KIND_INTERPOLATION_SEARCH
        return _kernel_last_interpolation_search(v, x, order)
    elseif kind === KIND_BIT_INTERPOLATION_SEARCH
        return _kernel_last_bit_interpolation_search(v, x, order)
    elseif kind === KIND_UNIFORM_STEP
        return _kernel_last_uniform_step(v, x, order)
    else
        return _kernel_last_binary_bracket(v, x, order)
    end
end

@inline function _search_first_hinted(
        kind::StrategyKind, v::AbstractVector, x, hint::Integer,
        order::Base.Order.Ordering,
    )
    if kind === KIND_BINARY_BRACKET
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_LINEAR_SCAN
        return _kernel_first_linear_scan(v, x, hint, order)
    elseif kind === KIND_SIMD_LINEAR_SCAN
        return _kernel_first_simd_linear_scan(v, x, hint, order)
    elseif kind === KIND_BRACKET_GALLOP
        return _kernel_first_bracket_gallop(v, x, hint, order)
    elseif kind === KIND_EXP_FROM_LEFT
        return _kernel_first_exp_from_left(v, x, hint, order)
    elseif kind === KIND_INTERPOLATION_SEARCH
        return _kernel_first_interpolation_search(v, x, order)
    elseif kind === KIND_BIT_INTERPOLATION_SEARCH
        return _kernel_first_bit_interpolation_search(v, x, order)
    elseif kind === KIND_UNIFORM_STEP
        return _kernel_first_uniform_step(v, x, order)
    else
        return _kernel_first_binary_bracket(v, x, order)
    end
end

@inline function _search_first_nohint(
        kind::StrategyKind, v::AbstractVector, x,
        order::Base.Order.Ordering,
    )
    if kind === KIND_BINARY_BRACKET
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_LINEAR_SCAN
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_SIMD_LINEAR_SCAN
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_BRACKET_GALLOP
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_EXP_FROM_LEFT
        return _kernel_first_binary_bracket(v, x, order)
    elseif kind === KIND_INTERPOLATION_SEARCH
        return _kernel_first_interpolation_search(v, x, order)
    elseif kind === KIND_BIT_INTERPOLATION_SEARCH
        return _kernel_first_bit_interpolation_search(v, x, order)
    elseif kind === KIND_UNIFORM_STEP
        return _kernel_first_uniform_step(v, x, order)
    else
        return _kernel_first_binary_bracket(v, x, order)
    end
end

# ---------------------------------------------------------------------------
# Per-strategy kind lookup. Used by the deprecation shims in
# `legacy_dispatch.jl` and by callers that need to convert a strategy
# struct to its enum tag.
# ---------------------------------------------------------------------------

"""
    strategy_kind(s::SearchStrategy) -> StrategyKind

Map a singleton strategy struct to its enum tag. Stateful strategies
(`GuesserHint`, `Auto`) do not have a tag and throw `ArgumentError`.
"""
function strategy_kind end

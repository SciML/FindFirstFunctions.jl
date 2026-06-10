# Strategy-framework equality search: `findequal(strategy, v, x[, hint])`.
# Returns an `Int` with the sentinel `firstindex(v) - 1` for "not found"
# (matching `Base.searchsortedlast`'s convention).
#
# Most strategies compose: run `search_first(strategy, v, x[, hint])` to
# find the candidate insertion point, then post-check whether `v[i] == x`.
# The `BisectThenSIMD` shortcut for `DenseVector{Int64}` dispatches into
# `findfirstsortedequal` directly.

"""
    findequal(strategy, v, x[, hint]; order = Base.Order.Forward) -> Int

Return the index of `x` in sorted `v` if present, or the sentinel
`firstindex(v) - 1` if `x` is absent. Type-stable `Int` return — the
sentinel matches the convention `Base.searchsortedlast` already uses for
"x precedes all of v".

The `strategy` argument can be:

  - A singleton strategy struct (`BinaryBracket()`, `BracketGallop()`,
    …) — back-compat with the v2 API.
  - A [`StrategyKind`](@ref) enum value (`KIND_BRACKET_GALLOP`, …) — the
    v3 preferred form.
  - A stateful strategy (`Auto`, `GuesserHint`) — dispatched via
    multimethod.

Most strategies are handled generically. The shortcut method on
[`BisectThenSIMD`](@ref) for `DenseVector{Int64}` skips the
`searchsortedfirst` path entirely.

For unsorted vectors, use [`findfirstequal`](@ref).
"""
@inline function findequal(
        strategy::SearchStrategy, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _findequal_generic_strategy(strategy, v, x, order)
end

@inline function findequal(
        strategy::SearchStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    i = searchsortedfirst(strategy, v, x, hint; order = order)
    return _findequal_postcheck(v, x, i)
end

# Enum-tagged form. `KIND_BISECT_THEN_SIMD` forwards to the struct form so
# the `DenseVector{Int64}` bisect-then-SIMD shortcut is reached — the
# generic `search_first` path would silently lose it.
@inline function findequal(
        kind::StrategyKind, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    kind === KIND_BISECT_THEN_SIMD &&
        return findequal(BisectThenSIMD(), v, x; order = order)
    i = search_first(kind, v, x; order = order)
    return _findequal_postcheck(v, x, i)
end

@inline function findequal(
        kind::StrategyKind, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    kind === KIND_BISECT_THEN_SIMD &&
        return findequal(BisectThenSIMD(), v, x, hint; order = order)
    i = search_first(kind, v, x, hint; order = order)
    return _findequal_postcheck(v, x, i)
end

@inline function _findequal_generic_strategy(strategy, v, x, order)
    i = searchsortedfirst(strategy, v, x; order = order)
    return _findequal_postcheck(v, x, i)
end

@inline function _findequal_postcheck(v::AbstractVector, x, i::Integer)
    if i > lastindex(v)
        return firstindex(v) - 1
    end
    @inbounds return isequal(v[i], x) ? Int(i) : (firstindex(v) - 1)
end

# Shortcut: BisectThenSIMD on DenseVector{Int64} uses the dedicated
# bisect-then-SIMD equality scan.
function findequal(
        ::BisectThenSIMD, v::DenseVector{Int64}, x::Int64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        return _findequal_postcheck(v, x, search_first(KIND_BINARY_BRACKET, v, x; order = order))
    end
    r = findfirstsortedequal(x, v)
    return r === nothing ? (firstindex(v) - 1) : r
end
findequal(
    s::BisectThenSIMD, v::DenseVector{Int64}, x::Int64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = findequal(s, v, x; order = order)

# Non-Int64 fallback for BisectThenSIMD.
function findequal(
        ::BisectThenSIMD, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    i = search_first(KIND_BINARY_BRACKET, v, x; order = order)
    return _findequal_postcheck(v, x, i)
end
findequal(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = findequal(s, v, x; order = order)

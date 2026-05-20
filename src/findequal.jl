# Strategy-framework equality search: `findequal(strategy, v, x[, hint])`.
# Returns an `Int` with the sentinel `firstindex(v) - 1` for "not found"
# (matching `Base.searchsortedlast`'s convention for "x precedes all of v").
# The `BisectThenSIMD` shortcut for `DenseVector{Int64}` dispatches into
# `findfirstsortedequal` directly; every other strategy composes via
# `searchsortedfirst` + a post-check.

"""
    findequal(strategy, v, x[, hint]; order = Base.Order.Forward) -> Int

Return the index of `x` in sorted `v` if present, or the sentinel
`firstindex(v) - 1` if `x` is absent. Type-stable `Int` return — the
sentinel matches the convention `Base.searchsortedlast` already uses for
"x precedes all of v", so callers can test for "not found" with
`i < firstindex(v)`.

For vectors with 1-based indexing (the Julia default), the sentinel is
exactly `0`, which is also `searchsortedlast`'s "x precedes all" return.
For [OffsetArrays](https://github.com/JuliaArrays/OffsetArrays.jl) and any
other vector whose `firstindex` is not `1`, the sentinel adjusts
accordingly — e.g. for a vector with `firstindex == -3`, the sentinel is
`-4`. Always test against `firstindex(v) - 1` (or equivalently
`i < firstindex(v)`), not against the literal `0`.

Most strategies are handled generically: run
`searchsortedfirst(strategy, v, x[, hint])` to find the candidate insertion
point, then check whether `v[i]` actually equals `x`. The shortcut method
on [`BisectThenSIMD`](@ref) for `DenseVector{Int64}` skips the
`searchsortedfirst` path entirely and uses the dedicated bisect-then-SIMD
equality scan that backs [`findfirstsortedequal`](@ref).

For unsorted vectors, use [`findfirstequal`](@ref) — it does not require
a sorted input and falls outside the strategy framework.
"""
@inline function findequal(
        strategy::SearchStrategy, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _findequal_generic(strategy, v, x, order)
end

@inline function findequal(
        strategy::SearchStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    i = searchsortedfirst(strategy, v, x, hint; order = order)
    return _findequal_postcheck(v, x, i)
end

@inline function _findequal_generic(strategy, v, x, order)
    i = searchsortedfirst(strategy, v, x; order = order)
    return _findequal_postcheck(v, x, i)
end

@inline function _findequal_postcheck(v::AbstractVector, x, i::Integer)
    if i > lastindex(v)
        return firstindex(v) - 1
    end
    @inbounds return isequal(v[i], x) ? Int(i) : (firstindex(v) - 1)
end

# Shortcut: BisectThenSIMD on DenseVector{Int64} uses the dedicated bisect-
# then-SIMD equality scan (same algorithm as `findfirstsortedequal`).
function findequal(
        ::BisectThenSIMD, v::DenseVector{Int64}, x::Int64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        return _findequal_generic(BinaryBracket(), v, x, order)
    end
    r = findfirstsortedequal(x, v)
    return r === nothing ? (firstindex(v) - 1) : r
end
# Hinted form ignores the hint — the bisect-then-SIMD algorithm does not
# benefit from a hint, and probing it would only waste cycles.
findequal(
    s::BisectThenSIMD, v::DenseVector{Int64}, x::Int64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = findequal(s, v, x; order = order)

# Non-Int64 fallback for BisectThenSIMD: use BinaryBracket + post-check.
function findequal(
        ::BisectThenSIMD, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return _findequal_generic(BinaryBracket(), v, x, order)
end
findequal(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = findequal(s, v, x; order = order)

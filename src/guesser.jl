# `Guesser` correlated-lookup helper + the public `looks_linear` probe it
# uses + the `GuesserHint` strategy dispatch that plugs a `Guesser` into the
# `searchsortedfirst`/`searchsortedlast` API.

"""
    looks_linear(v; threshold = 1e-2)

Determine if the abscissae `v` are regularly distributed, taking the standard deviation of
the difference between the array of abscissae with respect to the straight line linking
its first and last elements, normalized by the range of `v`. If this standard deviation is
below the given `threshold`, the vector looks linear (return true). Internal function -
interface may change.
"""
function looks_linear(v; threshold = 1.0e-2)
    length(v) <= 2 && return true
    x_0, x_f = first(v), last(v)
    N = length(v)
    x_span = x_f - x_0
    mean_x_dist = x_span / (N - 1)
    norm_var = sum((x_i - x_0 - (i - 1) * mean_x_dist)^2 for (i, x_i) in enumerate(v)) /
        (N * x_span^2)
    return norm_var < threshold^2
end

"""
    Guesser(v::AbstractVector; looks_linear_threshold = 1e-2)

Wrapper of the searched vector `v` which makes an informed guess for the next
correlated lookup by either

  - exploiting that `v` is sufficiently evenly spaced (linear-extrapolation guess), or
  - using the previous outcome (the cached `idx_prev`).

Pass a `Guesser` to [`GuesserHint`](@ref) to use it as a search strategy with
the dispatched [`searchsortedlast`](@ref Base.searchsortedlast) /
[`searchsortedfirst`](@ref Base.searchsortedfirst) API.
"""
struct Guesser{T <: AbstractVector}
    v::T
    idx_prev::Base.RefValue{Int}
    linear_lookup::Bool
end

function Guesser(v::AbstractVector; looks_linear_threshold = 1.0e-2)
    return Guesser(v, Ref(1), looks_linear(v; threshold = looks_linear_threshold))
end

function (g::Guesser)(x)
    (; v, idx_prev, linear_lookup) = g
    return if linear_lookup
        δx = x - first(v)
        iszero(δx) && return firstindex(v)
        f = δx / (last(v) - first(v))
        if isinf(f)
            f > 0 ? lastindex(v) : firstindex(v)
        else
            i_0, i_f = firstindex(v), lastindex(v)
            i_approx = f * (i_f - i_0) + i_0
            target_type = typeof(firstindex(v))
            if i_approx >= typemax(target_type)
                lastindex(v) + 1
            elseif i_approx <= typemin(target_type)
                firstindex(v) - 1
            else
                round(target_type, i_approx)
            end
        end
    else
        idx_prev[]
    end
end

# Note on ranges: `Base.searchsortedlast(r::AbstractRange, x, order)` is
# already O(1) (closed-form), so the strategies' fallback path through
# `BinaryBracket` (which delegates to that Base method) is already optimal
# for ranges. No special-case overlays needed.

# GuesserHint methods — strategy dispatch wrapper for the `Guesser`-based
# correlated search. Per-call cost: one `guesser(x)` evaluation + one
# `BracketGallop` call + one `idx_prev[]` write.
function Base.searchsortedlast(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    @assert v === s.guesser.v
    out = searchsortedlast(BracketGallop(), v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

function Base.searchsortedfirst(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    @assert v === s.guesser.v
    out = searchsortedfirst(BracketGallop(), v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

# GuesserHint ignores any externally-supplied hint (the Guesser carries its own).
Base.searchsortedlast(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)

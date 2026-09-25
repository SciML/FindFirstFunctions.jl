# `Guesser` correlated-lookup helper + the public `looks_linear` probe it
# uses + the `GuesserHint` strategy dispatch that plugs a `Guesser` into
# the v3 `searchsorted_last` / `searchsorted_first` API.

"""
    looks_linear(v; threshold = 1e-2)

Determine if the abscissae `v` are regularly distributed.
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

Wrapper of the searched vector `v` which makes an informed guess for the
next correlated lookup by either

  - exploiting that `v` is sufficiently evenly spaced (linear-extrapolation
    guess), or
  - using the previous outcome (the cached `idx_prev`).
"""
struct Guesser{T <: AbstractVector}
    v::T
    idx_prev::typeof(Ref(1))
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

# GuesserHint methods — stateful strategy, dispatches via its wrapper
# struct (not via a `StrategyKind`). The cost per call is one
# `guesser(x)` + one BracketGallop call + one `idx_prev[]` write.

@inline function searchsorted_last(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    @assert v === s.guesser.v
    out = searchsorted_last(KIND_BRACKET_GALLOP, v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

@inline function searchsorted_first(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    @assert v === s.guesser.v
    out = searchsorted_first(KIND_BRACKET_GALLOP, v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

# GuesserHint ignores any externally-supplied hint.
@inline searchsorted_last(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_last(s, v, x; order = order)
@inline searchsorted_first(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_first(s, v, x; order = order)

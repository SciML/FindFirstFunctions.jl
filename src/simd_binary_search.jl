# 8-way SIMD binary search for `DenseVector{Int64}` and `DenseVector{Float64}`.
# Each iteration loads 8 strided probes via `SIMD.vgather`, compares against
# the query, and reduces the result mask via `SIMD.bitmask` + `trailing_zeros`
# to pick the next subrange. The bracket shrinks by ~8× per step, giving an
# asymptotic ~log₈(n) iterations instead of log₂(n).
#
# Probe layout in `[lo, hi]` of length n = hi - lo + 1:
#   p_k = lo + ((k - 1) * (n - 1)) ÷ 7   for k ∈ 1..8
# so p_1 = lo, p_8 = hi, and the seven interior probes are evenly spaced.
# When n < 8 the probes can coincide; we fall back to a scalar bounded
# binary search on the inner loop for that case.

# Per-iteration SIMD shrink step. Returns (new_lo, new_hi, done, answer) where
# `done` is true once the bracket has either collapsed or we've isolated the
# answer at a boundary. The polarity of `pred_gt` controls whether we're
# implementing searchsortedlast (predicate `v > x`) or searchsortedfirst
# (predicate `v >= x`).
@inline function _simd_bsearch_step_last(
        v::DenseVector{T}, x::T, lo::Int, hi::Int,
    ) where {T <: Union{Int64, Float64}}
    # Compute the 8 probe indices. Using Int multiplication then division to
    # keep the indices integer; the (n-1) factor + integer division means
    # `p_1 == lo` and `p_8 == hi` exactly.
    n = hi - lo + 1
    # 8 quantile probes spanning [lo, hi]. Stored 0-based offsets here so
    # the SIMD.Vec{8,Int} ctor is one shuffle, not eight scalar adds.
    o0 = 0
    o1 = ((n - 1) * 1) ÷ 7
    o2 = ((n - 1) * 2) ÷ 7
    o3 = ((n - 1) * 3) ÷ 7
    o4 = ((n - 1) * 4) ÷ 7
    o5 = ((n - 1) * 5) ÷ 7
    o6 = ((n - 1) * 6) ÷ 7
    o7 = n - 1
    # SIMD.jl's vgather wants 1-based indices.
    idx = SIMD.Vec{8, Int}(
        (
            lo + o0, lo + o1, lo + o2, lo + o3,
            lo + o4, lo + o5, lo + o6, lo + o7,
        )
    )
    vals = SIMD.vgather(v, idx)
    mask = vals > x   # Vec{8, Bool}: lane k is true iff v[p_k] > x
    bm = SIMD.bitmask(mask)
    if bm == 0x00
        # All 8 probes have v[p] <= x. The answer is >= p_8 = hi. Since hi is
        # the current upper bracket bound, the answer is exactly hi (we know
        # v[hi+1] > x from the bracket invariant, or hi is lastindex(v)).
        return (lo, hi, true, hi)
    end
    tz = Int(trailing_zeros(bm))   # 0..7, index of first lane with v[p] > x
    if tz == 0
        # v[lo] > x already → answer is lo - 1.
        return (lo, hi, true, lo - 1)
    end
    # Lane tz is the first probe where v > x. Lane tz-1 had v <= x. The
    # answer lives in [p_{tz-1}, p_tz - 1].
    new_lo = lo + (((n - 1) * (tz - 1)) ÷ 7)
    new_hi = lo + (((n - 1) * tz) ÷ 7) - 1
    if new_lo > new_hi
        # Adjacent probes — answer is new_lo (since v[new_lo] <= x and
        # v[new_lo + 1] = v[p_tz] > x).
        return (lo, hi, true, new_lo)
    end
    return (new_lo, new_hi, false, 0)
end

# searchsortedfirst counterpart. Predicate: `v >= x`.
@inline function _simd_bsearch_step_first(
        v::DenseVector{T}, x::T, lo::Int, hi::Int,
    ) where {T <: Union{Int64, Float64}}
    n = hi - lo + 1
    o0 = 0
    o1 = ((n - 1) * 1) ÷ 7
    o2 = ((n - 1) * 2) ÷ 7
    o3 = ((n - 1) * 3) ÷ 7
    o4 = ((n - 1) * 4) ÷ 7
    o5 = ((n - 1) * 5) ÷ 7
    o6 = ((n - 1) * 6) ÷ 7
    o7 = n - 1
    idx = SIMD.Vec{8, Int}(
        (
            lo + o0, lo + o1, lo + o2, lo + o3,
            lo + o4, lo + o5, lo + o6, lo + o7,
        )
    )
    vals = SIMD.vgather(v, idx)
    mask = vals >= x
    bm = SIMD.bitmask(mask)
    if bm == 0x00
        # All probes v < x; answer is > p_8 = hi → hi + 1.
        return (lo, hi, true, hi + 1)
    end
    tz = Int(trailing_zeros(bm))
    if tz == 0
        # v[lo] >= x already → answer is lo.
        return (lo, hi, true, lo)
    end
    # Lane tz first with v >= x; lane tz-1 had v < x. Answer lives in
    # [p_{tz-1} + 1, p_tz].
    new_lo = lo + (((n - 1) * (tz - 1)) ÷ 7) + 1
    new_hi = lo + (((n - 1) * tz) ÷ 7)
    if new_lo > new_hi
        return (lo, hi, true, new_hi)
    end
    return (new_lo, new_hi, false, 0)
end

# Threshold: below this length, do a scalar bounded binary search instead of
# the SIMD step. The probe-position math needs n >= 8 to keep all 8 lanes at
# distinct indices; below that the gather either reloads the same index
# (correct but wasteful) or risks a zero-stride boundary case in some Julia
# versions. Picking the threshold at 16 gives some headroom and matches the
# n where scalar binary search is still very fast (4 compares).
const SIMD_BSEARCH_BASECASE = 16

@inline function _simd_bsearch_last(v::DenseVector{T}, x::T) where {T <: Union{Int64, Float64}}
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo - 1
    # Outer-bound checks short-circuit the common out-of-range queries.
    @inbounds if x < v[lo]
        return lo - 1
    end
    @inbounds if x >= v[hi]
        return hi
    end
    # Now v[lo] <= x < v[hi]; the answer is in [lo, hi - 1].
    hi -= 1
    while (hi - lo + 1) >= SIMD_BSEARCH_BASECASE
        lo, hi, done, ans = _simd_bsearch_step_last(v, x, lo, hi)
        done && return ans
    end
    # Basecase: scalar bounded binary search. Base.searchsortedlast accepts
    # (v, x, lo, hi, order) overloads.
    return searchsortedlast(v, x, lo, hi, Base.Order.Forward)
end

@inline function _simd_bsearch_first(v::DenseVector{T}, x::T) where {T <: Union{Int64, Float64}}
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo
    @inbounds if x <= v[lo]
        return lo
    end
    @inbounds if x > v[hi]
        return hi + 1
    end
    # Now v[lo] < x <= v[hi]; the answer is in [lo + 1, hi].
    lo += 1
    while (hi - lo + 1) >= SIMD_BSEARCH_BASECASE
        lo, hi, done, ans = _simd_bsearch_step_first(v, x, lo, hi)
        done && return ans
    end
    return searchsortedfirst(v, x, lo, hi, Base.Order.Forward)
end

# ===========================================================================
# Dispatch — Int64 and Float64 specialisations
# ===========================================================================

function Base.searchsortedlast(
        ::SIMDBinarySearch, v::DenseVector{Int64}, x::Int64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedlast(v, x, order)
    return _simd_bsearch_last(v, x)
end
function Base.searchsortedlast(
        ::SIMDBinarySearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedlast(v, x, order)
    return _simd_bsearch_last(v, x)
end
function Base.searchsortedfirst(
        ::SIMDBinarySearch, v::DenseVector{Int64}, x::Int64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(v, x, order)
    return _simd_bsearch_first(v, x)
end
function Base.searchsortedfirst(
        ::SIMDBinarySearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(v, x, order)
    return _simd_bsearch_first(v, x)
end

# Strategy ignores any hint that is supplied.
Base.searchsortedlast(
    s::SIMDBinarySearch, v::DenseVector{Int64}, x::Int64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedlast(
    s::SIMDBinarySearch, v::DenseVector{Float64}, x::Float64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::SIMDBinarySearch, v::DenseVector{Int64}, x::Int64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)
Base.searchsortedfirst(
    s::SIMDBinarySearch, v::DenseVector{Float64}, x::Float64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)

# Other eltypes / non-dense storage: fall back to BinaryBracket.
Base.searchsortedlast(
    ::SIMDBinarySearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::SIMDBinarySearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)
Base.searchsortedlast(
    s::SIMDBinarySearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::SIMDBinarySearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

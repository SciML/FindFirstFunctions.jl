# Kernel functions for each singleton strategy. Each kernel is a free
# function that performs the strategy's algorithm directly — no method
# dispatch, no Union returns, no wrapper struct.
#
# The kernels are called from the enum dispatcher in `kinds.jl` and from
# the legacy `Base.searchsortedlast(::S, ...)` shims in `legacy_dispatch.jl`.
# `Auto` and `GuesserHint` also call them (directly, by kind, for `Auto`;
# via the kind dispatcher, for `GuesserHint`).

# ===========================================================================
# Bracket helpers — backing `BracketGallop`
# ===========================================================================

# Expanding-binary-search bracket around a guess. The `searchsortedlast`
# polarity: when `x == v[guess]`, the answer is `>= guess` (gallop right).
function bracketstrictlymonotonic(
        v::AbstractVector,
        x,
        guess::T,
        o::Base.Order.Ordering,
    )::NTuple{2, keytype(v)} where {T <: Integer}
    bottom = firstindex(v)
    top = lastindex(v)
    if guess < bottom || guess > top
        return bottom, top
    else
        u = T(1)
        lo, hi = guess, min(guess + u, top)
        @inbounds if Base.Order.lt(o, x, v[lo])
            while lo > bottom && Base.Order.lt(o, x, v[lo])
                lo, hi = max(bottom, lo - u), lo
                u += u
            end
        else
            while hi < top && !Base.Order.lt(o, x, v[hi])
                lo, hi = hi, min(top, hi + u)
                u += u
            end
        end
    end
    return lo, hi
end

# Companion to `bracketstrictlymonotonic` for the `searchsortedfirst`
# polarity. When `x == v[lo]` the answer is `<= lo` (look for earlier
# duplicates) — so we use the inverted polarity `lt(o, v[lo], x)`.
function bracketstrictlymonotonic_first(
        v::AbstractVector,
        x,
        guess::T,
        o::Base.Order.Ordering,
    )::NTuple{2, keytype(v)} where {T <: Integer}
    bottom = firstindex(v)
    top = lastindex(v)
    if guess < bottom || guess > top
        return bottom, top
    else
        u = T(1)
        lo, hi = guess, min(guess + u, top)
        @inbounds if !Base.Order.lt(o, v[lo], x)
            while lo > bottom && !Base.Order.lt(o, v[lo], x)
                lo, hi = max(bottom, lo - u), lo
                u += u
            end
        else
            while hi < top && Base.Order.lt(o, v[hi], x)
                lo, hi = hi, min(top, hi + u)
                u += u
            end
        end
    end
    return lo, hi
end

# ===========================================================================
# Exponential-search helpers — backing `ExpFromLeft`
# ===========================================================================

# Finds the smallest index `y` in `[lo, hi]` with `!lt(order, v[y], x)`.
Base.@propagate_inbounds function searchsortedfirstexp(
        v::AbstractVector,
        x,
        lo::Integer = firstindex(v),
        hi::Integer = lastindex(v),
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    for i in 0:4
        ind = lo + i
        ind > hi && return ind
        !Base.Order.lt(order, v[ind], x) && return ind
    end
    n = 3
    tn2 = 2^n
    tn2m1 = 2^(n - 1)
    ind = lo + tn2
    while ind <= hi
        !Base.Order.lt(order, v[ind], x) &&
            return searchsortedfirst(v, x, lo + tn2 - tn2m1, ind, order)
        tn2 *= 2
        tn2m1 *= 2
        ind = lo + tn2
    end
    return searchsortedfirst(v, x, lo + tn2 - tn2m1, hi, order)
end

# Finds the largest `y` in `[lo, hi]` with `!lt(order, x, v[y])`.
Base.@propagate_inbounds function searchsortedlastexp(
        v::AbstractVector,
        x,
        lo::Integer = firstindex(v),
        hi::Integer = lastindex(v),
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    for i in 0:4
        ind = lo + i
        ind > hi && return hi
        Base.Order.lt(order, x, v[ind]) && return ind - 1
    end
    n = 3
    tn2 = 2^n
    tn2m1 = 2^(n - 1)
    ind = lo + tn2
    while ind <= hi
        Base.Order.lt(order, x, v[ind]) &&
            return searchsortedlast(v, x, lo + tn2 - tn2m1, ind, order)
        tn2 *= 2
        tn2m1 *= 2
        ind = lo + tn2
    end
    return searchsortedlast(v, x, lo + tn2 - tn2m1, hi, order)
end

# ===========================================================================
# Kernel: BinaryBracket — plain `Base.searchsortedlast` / `Base.searchsortedfirst`.
# ===========================================================================

@inline _kernel_last_binary_bracket(v::AbstractVector, x, order::Base.Order.Ordering) =
    searchsortedlast(v, x, order)
@inline _kernel_first_binary_bracket(v::AbstractVector, x, order::Base.Order.Ordering) =
    searchsortedfirst(v, x, order)

# ===========================================================================
# Kernel: LinearScan — walk ±1 from the hint.
# ===========================================================================

function _kernel_last_linear_scan(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    if hi < lo
        return lo - 1   # empty vector
    end
    i = clamp(hint, lo, hi)
    @inbounds if Base.Order.lt(order, x, v[i])
        # v[i] > x → retreat
        while i > lo
            i -= 1
            !Base.Order.lt(order, x, v[i]) && return i
        end
        return lo - 1   # x precedes all of v
    else
        # v[i] ≤ x → try to advance
        while i < hi
            Base.Order.lt(order, x, v[i + 1]) && return i
            i += 1
        end
        return hi
    end
end

function _kernel_first_linear_scan(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    if hi < lo
        return lo
    end
    i = clamp(hint, lo, hi)
    @inbounds if Base.Order.lt(order, v[i], x)
        # v[i] < x → advance
        while i < hi
            i += 1
            !Base.Order.lt(order, v[i], x) && return i
        end
        return hi + 1   # x exceeds all of v
    else
        # v[i] ≥ x → try to retreat
        while i > lo
            !Base.Order.lt(order, v[i - 1], x) && (i -= 1; continue)
            return i
        end
        return lo
    end
end

# ===========================================================================
# Kernel: SIMDLinearScan — specialized forward walk for DenseVector{Int64}
# and DenseVector{Float64}. Falls back to scalar LinearScan otherwise.
# ===========================================================================

@inline function _simdscan_last_specialized(
        v::Union{DenseVector{Int64}, DenseVector{Float64}},
        x, hint::Integer,
        order::Base.Order.Ordering,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo - 1
    i = clamp(hint, lo, hi)
    @inbounds vi = v[i]
    if Base.Order.lt(order, x, vi)
        # `v[i]` is past the answer in this ordering — backward walk (scalar).
        while i > lo
            i -= 1
            @inbounds !Base.Order.lt(order, x, v[i]) && return i
        end
        return lo - 1
    end
    i == hi && return hi
    start = i + 1
    len = hi - start + 1
    offset = if order === Base.Order.Forward
        GC.@preserve v _simd_first_gt(x, pointer(v, start), Int64(len))
    else
        GC.@preserve v _simd_first_lt(x, pointer(v, start), Int64(len))
    end
    return offset < 0 ? hi : (start + offset) - 1
end

@inline function _simdscan_first_specialized(
        v::Union{DenseVector{Int64}, DenseVector{Float64}},
        x, hint::Integer,
        order::Base.Order.Ordering,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo
    i = clamp(hint, lo, hi)
    @inbounds vi = v[i]
    if Base.Order.lt(order, vi, x)
        i == hi && return hi + 1
        start = i + 1
        len = hi - start + 1
        offset = if order === Base.Order.Forward
            GC.@preserve v _simd_first_ge(x, pointer(v, start), Int64(len))
        else
            GC.@preserve v _simd_first_le(x, pointer(v, start), Int64(len))
        end
        return offset < 0 ? hi + 1 : start + offset
    end
    while i > lo
        @inbounds Base.Order.lt(order, v[i - 1], x) && return i
        i -= 1
    end
    return lo
end

# Whether the ordering is one of the two ordering singletons SIMD supports.
@inline function _simd_supported_order(order::Base.Order.Ordering)
    return order === Base.Order.Forward || order === Base.Order.Reverse
end

# Static-dispatch entry: Int64 and Float64 dense vectors get the SIMD path
# (under supported orderings); everything else falls back to scalar LinearScan.
@inline function _kernel_last_simd_linear_scan(
        v::DenseVector{Int64}, x::Int64, hint::Integer, order::Base.Order.Ordering,
    )
    _simd_supported_order(order) ||
        return _kernel_last_linear_scan(v, x, hint, order)
    return _simdscan_last_specialized(v, x, hint, order)
end
@inline function _kernel_last_simd_linear_scan(
        v::DenseVector{Float64}, x::Float64, hint::Integer, order::Base.Order.Ordering,
    )
    _simd_supported_order(order) ||
        return _kernel_last_linear_scan(v, x, hint, order)
    return _simdscan_last_specialized(v, x, hint, order)
end
@inline _kernel_last_simd_linear_scan(
    v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
) = _kernel_last_linear_scan(v, x, hint, order)

@inline function _kernel_first_simd_linear_scan(
        v::DenseVector{Int64}, x::Int64, hint::Integer, order::Base.Order.Ordering,
    )
    _simd_supported_order(order) ||
        return _kernel_first_linear_scan(v, x, hint, order)
    return _simdscan_first_specialized(v, x, hint, order)
end
@inline function _kernel_first_simd_linear_scan(
        v::DenseVector{Float64}, x::Float64, hint::Integer, order::Base.Order.Ordering,
    )
    _simd_supported_order(order) ||
        return _kernel_first_linear_scan(v, x, hint, order)
    return _simdscan_first_specialized(v, x, hint, order)
end
@inline _kernel_first_simd_linear_scan(
    v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
) = _kernel_first_linear_scan(v, x, hint, order)

# ===========================================================================
# Kernel: BracketGallop — bracketstrictlymonotonic + bounded binary search.
# ===========================================================================

@inline function _kernel_last_bracket_gallop(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo, hi = bracketstrictlymonotonic(v, x, hint, order)
    return searchsortedlast(v, x, lo, hi, order)
end

@inline function _kernel_first_bracket_gallop(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo, hi = bracketstrictlymonotonic_first(v, x, hint, order)
    return searchsortedfirst(v, x, lo, hi, order)
end

# ===========================================================================
# Kernel: ExpFromLeft — galloping forward from a left-bound hint.
# ===========================================================================

function _kernel_first_exp_from_left(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    if isempty(v)
        return lo
    end
    h = clamp(hint, lo, hi)
    @inbounds if !Base.Order.lt(order, v[h], x)
        return searchsortedfirst(v, x, order)
    end
    return searchsortedfirstexp(v, x, h, hi, order)
end

function _kernel_last_exp_from_left(
        v::AbstractVector, x, hint::Integer, order::Base.Order.Ordering,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    if isempty(v)
        return lo - 1
    end
    h = clamp(hint, lo, hi)
    @inbounds if Base.Order.lt(order, x, v[h])
        return searchsortedlast(v, x, order)
    end
    return searchsortedlastexp(v, x, h, hi, order)
end

# ===========================================================================
# Kernel: InterpolationSearch — extrapolate a guess + bounded binary search.
# ===========================================================================

@inline function _interp_guess(v::AbstractVector, x, lo::Integer, hi::Integer)
    @inbounds vlo = v[lo]
    @inbounds vhi = v[hi]
    span = vhi - vlo
    iszero(span) && return lo
    f = (x - vlo) / span
    if !isfinite(f)
        return f > 0 ? hi : lo
    end
    g = lo + round(Int, f * (hi - lo))
    return clamp(g, lo, hi)
end

function _kernel_last_interpolation_search_numeric(
        v::AbstractVector{<:Number}, x::Number, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    g = _interp_guess(v, x, lo, hi)
    return _kernel_last_bracket_gallop(v, x, g, order)
end

function _kernel_first_interpolation_search_numeric(
        v::AbstractVector{<:Number}, x::Number, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo
    g = _interp_guess(v, x, lo, hi)
    return _kernel_first_bracket_gallop(v, x, g, order)
end

@inline _kernel_last_interpolation_search(
    v::AbstractVector{<:Number}, x::Number, order::Base.Order.Ordering,
) = _kernel_last_interpolation_search_numeric(v, x, order)
@inline _kernel_last_interpolation_search(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_last_binary_bracket(v, x, order)

@inline _kernel_first_interpolation_search(
    v::AbstractVector{<:Number}, x::Number, order::Base.Order.Ordering,
) = _kernel_first_interpolation_search_numeric(v, x, order)
@inline _kernel_first_interpolation_search(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_first_binary_bracket(v, x, order)

# ===========================================================================
# Kernel: BitInterpolationSearch — InterpolationSearch on IEEE bit pattern
# of positive Float64.
# ===========================================================================

@inline function _bit_interp_guess_f64(
        v::DenseVector{Float64}, x::Float64, lo::Integer, hi::Integer,
        order::Base.Order.Ordering,
    )
    @inbounds vlo_bits = reinterpret(UInt64, v[lo])
    @inbounds vhi_bits = reinterpret(UInt64, v[hi])
    xu = reinterpret(UInt64, x)
    return if order === Base.Order.Forward
        span = vhi_bits - vlo_bits
        if iszero(span)
            lo
        elseif xu <= vlo_bits
            lo
        elseif xu >= vhi_bits
            hi
        else
            num = xu - vlo_bits
            f = Float64(num) / Float64(span)
            clamp(lo + round(Int, f * (hi - lo)), lo, hi)
        end
    else
        span = vlo_bits - vhi_bits
        if iszero(span)
            lo
        elseif xu >= vlo_bits
            lo
        elseif xu <= vhi_bits
            hi
        else
            num = vlo_bits - xu
            f = Float64(num) / Float64(span)
            clamp(lo + round(Int, f * (hi - lo)), lo, hi)
        end
    end
end

@inline function _bit_interp_eligible(v::DenseVector{Float64}, x::Float64, lo, hi, order)
    _simd_supported_order(order) || return false
    @inbounds return v[lo] > 0.0 && isfinite(v[lo]) &&
        v[hi] > 0.0 && isfinite(v[hi]) &&
        x > 0.0 && isfinite(x)
end

function _kernel_last_bit_interpolation_search_f64(
        v::DenseVector{Float64}, x::Float64, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    _bit_interp_eligible(v, x, lo, hi, order) ||
        return _kernel_last_binary_bracket(v, x, order)
    g = _bit_interp_guess_f64(v, x, lo, hi, order)
    return _kernel_last_bracket_gallop(v, x, g, order)
end

function _kernel_first_bit_interpolation_search_f64(
        v::DenseVector{Float64}, x::Float64, order::Base.Order.Ordering,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo
    _bit_interp_eligible(v, x, lo, hi, order) ||
        return _kernel_first_binary_bracket(v, x, order)
    g = _bit_interp_guess_f64(v, x, lo, hi, order)
    return _kernel_first_bracket_gallop(v, x, g, order)
end

@inline _kernel_last_bit_interpolation_search(
    v::DenseVector{Float64}, x::Float64, order::Base.Order.Ordering,
) = _kernel_last_bit_interpolation_search_f64(v, x, order)
@inline _kernel_last_bit_interpolation_search(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_last_interpolation_search(v, x, order)

@inline _kernel_first_bit_interpolation_search(
    v::DenseVector{Float64}, x::Float64, order::Base.Order.Ordering,
) = _kernel_first_bit_interpolation_search_f64(v, x, order)
@inline _kernel_first_bit_interpolation_search(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_first_interpolation_search(v, x, order)

# ===========================================================================
# Kernel: UniformStep — O(1) closed-form lookup for AbstractRange.
# ===========================================================================

@inline _uniformstep_supported_order(::Base.Order.ForwardOrdering) = true
@inline _uniformstep_supported_order(::Base.Order.ReverseOrdering) = true
@inline _uniformstep_supported_order(::Base.Order.Ordering) = false

@inline function _uniformstep_searchsortedlast(
        r::AbstractRange, x, order::Base.Order.Ordering,
    )
    isempty(r) && return firstindex(r) - 1
    s = step(r)
    iszero(s) && return lastindex(r)
    diff = x - first(r)
    if diff isa AbstractFloat && !isfinite(diff)
        return isnan(diff) ? (firstindex(r) - 1) :
            (diff > 0) ⊻ (s < 0) ? lastindex(r) : firstindex(r) - 1
    end
    nm1 = length(r) - 1
    f = fld(diff, s)
    i = if f < 0
        firstindex(r) - 1
    elseif f >= nm1
        lastindex(r)
    else
        firstindex(r) + Int(f)
    end
    @inbounds if i < lastindex(r) && !Base.Order.lt(order, x, r[i + 1])
        return i + 1
    elseif i >= firstindex(r) && i <= lastindex(r) && Base.Order.lt(order, x, r[i])
        return i - 1
    end
    return i
end

@inline function _uniformstep_searchsortedfirst(
        r::AbstractRange, x, order::Base.Order.Ordering,
    )
    isempty(r) && return firstindex(r)
    s = step(r)
    iszero(s) && return firstindex(r)
    diff = x - first(r)
    if diff isa AbstractFloat && !isfinite(diff)
        return isnan(diff) ? (lastindex(r) + 1) :
            (diff > 0) ⊻ (s < 0) ? lastindex(r) + 1 : firstindex(r)
    end
    nm1 = length(r) - 1
    f = cld(diff, s)
    i = if f <= 0
        firstindex(r)
    elseif f > nm1
        lastindex(r) + 1
    else
        firstindex(r) + Int(f)
    end
    @inbounds if i > firstindex(r) && i <= lastindex(r) + 1 &&
            !Base.Order.lt(order, r[i - 1], x)
        return i - 1
    end
    @inbounds if i <= lastindex(r) && Base.Order.lt(order, r[i], x)
        return i + 1
    end
    return i
end

@inline _kernel_last_uniform_step(
    v::AbstractRange, x, order::Base.Order.Ordering,
) = _uniformstep_supported_order(order) ?
    _uniformstep_searchsortedlast(v, x, order) :
    _kernel_last_binary_bracket(v, x, order)
@inline _kernel_last_uniform_step(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_last_binary_bracket(v, x, order)

@inline _kernel_first_uniform_step(
    v::AbstractRange, x, order::Base.Order.Ordering,
) = _uniformstep_supported_order(order) ?
    _uniformstep_searchsortedfirst(v, x, order) :
    _kernel_first_binary_bracket(v, x, order)
@inline _kernel_first_uniform_step(
    v::AbstractVector, x, order::Base.Order.Ordering,
) = _kernel_first_binary_bracket(v, x, order)

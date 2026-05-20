# Per-strategy `Base.searchsortedlast` / `Base.searchsortedfirst` dispatch.
# Each strategy gets one dispatch block plus any internal helpers it needs
# (`bracketstrictlymonotonic*` for `BracketGallop`, `searchsortedfirstexp`
# for `ExpFromLeft`, `_interp_guess` for `InterpolationSearch`, etc.).
#
# `Auto`'s per-query and batched dispatch lives in `auto.jl` / `batched.jl`;
# `GuesserHint`'s lives in `guesser.jl`.

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
# polarity. Original uses `lt(o, x, v[lo])` (i.e., `x < v[lo]`), which is
# right for `searchsortedlast`: when `x == v[lo]`, the answer is `>= lo` so
# we gallop right. For `searchsortedfirst`, when `x == v[lo]` the answer is
# `<= lo` (look for earlier duplicates) — so we need the inverted polarity
# `lt(o, v[lo], x)`. Without this, BracketGallop.searchsortedfirst returns
# the wrong index when the hint lands on a run of duplicates.
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
            # v[lo] >= x → answer is <= lo, gallop left.
            while lo > bottom && !Base.Order.lt(o, v[lo], x)
                lo, hi = max(bottom, lo - u), lo
                u += u
            end
        else
            # v[lo] < x → answer is > lo, gallop right.
            while hi < top && Base.Order.lt(o, v[hi], x)
                lo, hi = hi, min(top, hi + u)
                u += u
            end
        end
    end
    return lo, hi
end

# ===========================================================================
# Exponential-search helper — backing `ExpFromLeft`
# ===========================================================================

# Exponential search forward from `lo`, then bounded binary search inside the
# final bracket. Used internally by `ExpFromLeft`.
Base.@propagate_inbounds function searchsortedfirstexp(
        v::AbstractVector,
        x,
        lo::Integer = firstindex(v),
        hi::Integer = lastindex(v),
    )
    # Linear search for first few elements
    for i in 0:4
        ind = lo + i
        ind > hi && return ind
        x <= v[ind] && return ind
    end
    # Exponential search with doubling steps
    n = 3
    tn2 = 2^n
    tn2m1 = 2^(n - 1)
    ind = lo + tn2
    while ind <= hi
        x <= v[ind] &&
            return searchsortedfirst(v, x, lo + tn2 - tn2m1, ind, Base.Order.Forward)
        tn2 *= 2
        tn2m1 *= 2
        ind = lo + tn2
    end
    return searchsortedfirst(v, x, lo + tn2 - tn2m1, hi, Base.Order.Forward)
end

# ===========================================================================
# Strategy: BinaryBracket — ignore any hint, delegate to `Base`
# ===========================================================================

Base.searchsortedlast(
    ::BinaryBracket, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(v, x, order)
Base.searchsortedfirst(
    ::BinaryBracket, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(v, x, order)
Base.searchsortedlast(
    s::BinaryBracket, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::BinaryBracket, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)

# ===========================================================================
# Strategy: LinearScan — walk ±1 from the hint
# ===========================================================================

function Base.searchsortedlast(
        ::LinearScan, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
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

function Base.searchsortedfirst(
        ::LinearScan, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
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

# LinearScan without a hint falls back to BinaryBracket.
Base.searchsortedlast(
    s::LinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::LinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ===========================================================================
# Strategy: SIMDLinearScan — specialized forward walk for DenseVector{Int64}
# and DenseVector{Float64}. Backward walks reuse the scalar LinearScan path
# (rare from a good hint, and the SIMD primitive only exists for the
# forward-scan direction).
# ===========================================================================

@inline function _simdscan_last_specialized(
        v::Union{DenseVector{Int64}, DenseVector{Float64}}, x, hint::Integer,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo - 1
    i = clamp(hint, lo, hi)
    @inbounds vi = v[i]
    if vi > x
        # Backward walk (scalar).
        while i > lo
            i -= 1
            @inbounds v[i] <= x && return i
        end
        return lo - 1
    end
    i == hi && return hi
    start = i + 1
    len = hi - start + 1
    offset = GC.@preserve v _simd_first_gt(x, pointer(v, start), Int64(len))
    return offset < 0 ? hi : (start + offset) - 1
end

@inline function _simdscan_first_specialized(
        v::Union{DenseVector{Int64}, DenseVector{Float64}}, x, hint::Integer,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    hi < lo && return lo
    i = clamp(hint, lo, hi)
    @inbounds vi = v[i]
    if vi < x
        i == hi && return hi + 1
        start = i + 1
        len = hi - start + 1
        offset = GC.@preserve v _simd_first_ge(x, pointer(v, start), Int64(len))
        return offset < 0 ? hi + 1 : start + offset
    end
    while i > lo
        @inbounds v[i - 1] >= x && (i -= 1; continue)
        return i
    end
    return lo
end

function Base.searchsortedlast(
        ::SIMDLinearScan, v::DenseVector{Int64}, x::Int64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint)
end
function Base.searchsortedlast(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Int64}, x::Int64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint)
end

# Other eltypes fall back to the scalar LinearScan walk.
Base.searchsortedlast(
    ::SIMDLinearScan, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(LinearScan(), v, x, hint; order = order)
Base.searchsortedfirst(
    ::SIMDLinearScan, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(LinearScan(), v, x, hint; order = order)

# No hint → BinaryBracket.
Base.searchsortedlast(
    ::SIMDLinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::SIMDLinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ===========================================================================
# Strategy: BracketGallop — bracketstrictlymonotonic + bounded binary search
# ===========================================================================

function Base.searchsortedlast(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    lo, hi = bracketstrictlymonotonic(v, x, hint, order)
    return searchsortedlast(v, x, lo, hi, order)
end

function Base.searchsortedfirst(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    lo, hi = bracketstrictlymonotonic_first(v, x, hint, order)
    return searchsortedfirst(v, x, lo, hi, order)
end

# BracketGallop without a hint falls back to BinaryBracket.
Base.searchsortedlast(
    ::BracketGallop, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::BracketGallop, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ===========================================================================
# Strategy: ExpFromLeft — galloping forward from a left-bound hint.
#
# Contract: callers pass `hint` such that the answer is ≥ `hint`. When that
# isn't true (hint is past the answer), we fall back to a full
# `searchsortedlast`/`searchsortedfirst` — the batched-sorted loop sets
# `hint = prev_result`, which always satisfies this for sorted queries, so
# the fallback is only exercised by arbitrary single-query callers.
# ===========================================================================

function Base.searchsortedfirst(
        ::ExpFromLeft, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    lo = firstindex(v)
    hi = lastindex(v)
    if isempty(v)
        return lo
    end
    h = clamp(hint, lo, hi)
    # `searchsortedfirst` semantics: smallest i with v[i] >= x. We can only
    # gallop forward from `h` when v[h] < x (then the answer is strictly
    # > h). When v[h] >= x, the first occurrence of `x` may be at index
    # ≤ h (duplicates to the left), so fall back to a full search rather
    # than risk skipping past earlier duplicates.
    @inbounds if !Base.Order.lt(order, v[h], x)
        return searchsortedfirst(v, x, order)
    end
    return order === Base.Order.Forward ?
        searchsortedfirstexp(v, x, h, hi) :
        searchsortedfirst(v, x, h, hi, order)
end

function Base.searchsortedlast(
        ::ExpFromLeft, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
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
    if order === Base.Order.Forward
        y = searchsortedfirstexp(v, x, h, hi)
        return if y > hi
            hi
        else
            @inbounds v[y] == x ? y : y - 1
        end
    else
        return searchsortedlast(v, x, h, hi, order)
    end
end

# ExpFromLeft without a hint falls back to BinaryBracket.
Base.searchsortedlast(
    ::ExpFromLeft, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::ExpFromLeft, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ===========================================================================
# Strategy: InterpolationSearch — extrapolate a guess, then bounded binary
# search around it.
# ===========================================================================

@inline function _interp_guess(v::AbstractVector, x, lo::Integer, hi::Integer)
    @inbounds vlo = v[lo]
    @inbounds vhi = v[hi]
    span = vhi - vlo
    iszero(span) && return lo
    # Linear extrapolation: how far is x along [vlo, vhi]?
    f = (x - vlo) / span
    if !isfinite(f)
        return f > 0 ? hi : lo
    end
    g = lo + round(Int, f * (hi - lo))
    return clamp(g, lo, hi)
end

function Base.searchsortedlast(
        ::InterpolationSearch, v::AbstractVector{<:Number}, x::Number;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        # Linear interpolation doesn't carry over to reverse order; fall back
        return searchsortedlast(v, x, order)
    end
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    g = _interp_guess(v, x, lo, hi)
    return searchsortedlast(BracketGallop(), v, x, g; order = order)
end

function Base.searchsortedfirst(
        ::InterpolationSearch, v::AbstractVector{<:Number}, x::Number;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        return searchsortedfirst(v, x, order)
    end
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo
    g = _interp_guess(v, x, lo, hi)
    return searchsortedfirst(BracketGallop(), v, x, g; order = order)
end

# InterpolationSearch ignores any hint; pass-through.
Base.searchsortedlast(
    s::InterpolationSearch, v::AbstractVector{<:Number}, x::Number, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::InterpolationSearch, v::AbstractVector{<:Number}, x::Number, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)

# InterpolationSearch on non-numeric data falls back to BinaryBracket.
Base.searchsortedlast(
    ::InterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::InterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)
Base.searchsortedlast(
    s::InterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::InterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ===========================================================================
# Strategy: BitInterpolationSearch — InterpolationSearch on the IEEE bit
# pattern of positive Float64. Cheaper than reinterpret-as-array because we
# only need two endpoint reads and one query bitcast per call.
# ===========================================================================

@inline function _bit_interp_guess_f64(
        v::DenseVector{Float64}, x::Float64, lo::Integer, hi::Integer,
    )
    @inbounds vlo_bits = reinterpret(UInt64, v[lo])
    @inbounds vhi_bits = reinterpret(UInt64, v[hi])
    xu = reinterpret(UInt64, x)
    span = vhi_bits - vlo_bits
    iszero(span) && return lo
    if xu <= vlo_bits
        return lo
    elseif xu >= vhi_bits
        return hi
    end
    num = xu - vlo_bits
    f = Float64(num) / Float64(span)
    g = lo + round(Int, f * (hi - lo))
    return clamp(g, lo, hi)
end

function Base.searchsortedlast(
        ::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        return searchsortedlast(v, x, order)
    end
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    @inbounds if v[lo] <= 0.0 || !isfinite(v[lo]) || x <= 0.0 || !isfinite(x)
        return searchsortedlast(BinaryBracket(), v, x; order = order)
    end
    g = _bit_interp_guess_f64(v, x, lo, hi)
    return searchsortedlast(BracketGallop(), v, x, g; order = order)
end

function Base.searchsortedfirst(
        ::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    if order !== Base.Order.Forward
        return searchsortedfirst(v, x, order)
    end
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo
    @inbounds if v[lo] <= 0.0 || !isfinite(v[lo]) || x <= 0.0 || !isfinite(x)
        return searchsortedfirst(BinaryBracket(), v, x; order = order)
    end
    g = _bit_interp_guess_f64(v, x, lo, hi)
    return searchsortedfirst(BracketGallop(), v, x, g; order = order)
end

# Hint pass-through (bit-interp ignores externally-supplied hints).
Base.searchsortedlast(
    s::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(s, v, x; order = order)

# Non-Float64 / non-dense eltypes: fall back to plain InterpolationSearch.
Base.searchsortedlast(
    ::BitInterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(InterpolationSearch(), v, x; order = order)
Base.searchsortedfirst(
    ::BitInterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(InterpolationSearch(), v, x; order = order)
Base.searchsortedlast(
    ::BitInterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(InterpolationSearch(), v, x; order = order)
Base.searchsortedfirst(
    ::BitInterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(InterpolationSearch(), v, x; order = order)

# ===========================================================================
# Strategy: BisectThenSIMD — equality-search; positional dispatch falls back
# to BinaryBracket. (The `findequal(BisectThenSIMD(), v, x)` shortcut lives
# in `findequal.jl`.)
# ===========================================================================

Base.searchsortedlast(
    ::BisectThenSIMD, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::BisectThenSIMD, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)
Base.searchsortedlast(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

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
# final bracket. Used internally by `ExpFromLeft`. The `order` parameter
# makes the comparison polarity-aware so `ExpFromLeft` works natively under
# both `Base.Order.Forward` (ascending) and `Base.Order.Reverse` (descending)
# without falling back to plain `Base.searchsortedfirst`.
#
# Finds the smallest index `y` in `[lo, hi]` with `!lt(order, v[y], x)`
# (equivalent to `v[y] >= x` under Forward, `v[y] <= x` under Reverse).
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

# Sibling of `searchsortedfirstexp` for the `searchsortedlast` polarity:
# finds the largest `y` in `[lo, hi]` with `!lt(order, x, v[y])`
# (equivalent to `v[y] <= x` under Forward, `v[y] >= x` under Reverse).
# Uses the *strict* comparison `lt(order, x, v[ind])` to detect the crossing
# past `x`, then returns `ind - 1`. Without this dedicated helper, callers
# would have to post-process `searchsortedfirstexp`'s result and re-scan for
# duplicates of `x` to find the last occurrence.
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
# and DenseVector{Float64}. Backward walks reuse a scalar walk (rare from a
# good hint). The SIMD primitive is order-aware: under `Forward`, scans for
# the first lane with `v[i] > x` (or `>= x` for searchsortedfirst); under
# `Reverse`, scans for the first lane with `v[i] < x` (or `<= x`). Any other
# ordering falls back to scalar `LinearScan`.
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
    # SIMD forward scan for the first lane that crosses the threshold.
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
        # `v[i]` is before the answer — SIMD-scan forward for the first lane
        # that meets-or-passes the search target.
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
    # `v[i]` meets or passes — retreat (scalar).
    while i > lo
        @inbounds Base.Order.lt(order, v[i - 1], x) && return i
        i -= 1
    end
    return lo
end

# Dispatch helper: only `Forward` and `Reverse` orderings use the SIMD path;
# anything else (custom `By`, `Lt`, etc.) falls back to scalar `LinearScan`.
@inline function _simd_supported_order(order::Base.Order.Ordering)
    return order === Base.Order.Forward || order === Base.Order.Reverse
end

function Base.searchsortedlast(
        ::SIMDLinearScan, v::DenseVector{Int64}, x::Int64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    _simd_supported_order(order) ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint, order)
end
function Base.searchsortedlast(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    _simd_supported_order(order) ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint, order)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Int64}, x::Int64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    _simd_supported_order(order) ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint, order)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    _simd_supported_order(order) ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint, order)
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
    # `searchsortedfirst` semantics: smallest i with `!lt(order, v[i], x)`.
    # We can only gallop forward from `h` when `v[h]` is still "before" the
    # answer in the ordering — `lt(order, v[h], x)`. Otherwise the first
    # occurrence may be at index ≤ h (duplicates) and we'd skip past it.
    @inbounds if !Base.Order.lt(order, v[h], x)
        return searchsortedfirst(v, x, order)
    end
    return searchsortedfirstexp(v, x, h, hi, order)
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
    return searchsortedlastexp(v, x, h, hi, order)
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
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    # `_interp_guess` works for both `Forward` and `Reverse`: for a
    # `Reverse`-sorted (decreasing) vector, `vhi - vlo < 0` and
    # `x - vlo < 0` for queries inside `[vhi, vlo]`, so the ratio
    # `(x - vlo) / (vhi - vlo)` still lands in `[0, 1]` and gives the
    # correct fractional position. Falls back to `BinaryBracket` for any
    # other ordering via `BracketGallop`.
    g = _interp_guess(v, x, lo, hi)
    return searchsortedlast(BracketGallop(), v, x, g; order = order)
end

function Base.searchsortedfirst(
        ::InterpolationSearch, v::AbstractVector{<:Number}, x::Number;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
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
# only need two endpoint reads and one query bitcast per call. Order-aware:
# under `Forward` (ascending bit patterns) and `Reverse` (descending bit
# patterns) the guess formula is the same fractional linear extrapolation,
# only the directionality of the comparison swaps.
# ===========================================================================

@inline function _bit_interp_guess_f64(
        v::DenseVector{Float64}, x::Float64, lo::Integer, hi::Integer,
        order::Base.Order.Ordering,
    )
    @inbounds vlo_bits = reinterpret(UInt64, v[lo])
    @inbounds vhi_bits = reinterpret(UInt64, v[hi])
    xu = reinterpret(UInt64, x)
    return if order === Base.Order.Forward
        # Forward: vlo_bits ≤ vhi_bits. Standard fractional interp on
        # unsigned bit patterns.
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
        # Reverse: vlo_bits ≥ vhi_bits. Mirror the arithmetic.
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

# `Forward` requires both endpoints strictly positive (negative / subnormal
# / non-finite Float64 bit patterns are not monotonic with float value).
# `Reverse` requires the same on both endpoints. For unsupported orderings
# (custom `By`, `Lt`, …) fall back to `BinaryBracket`.
@inline function _bit_interp_eligible(v::DenseVector{Float64}, x::Float64, lo, hi, order)
    _simd_supported_order(order) || return false
    @inbounds return v[lo] > 0.0 && isfinite(v[lo]) &&
        v[hi] > 0.0 && isfinite(v[hi]) &&
        x > 0.0 && isfinite(x)
end

function Base.searchsortedlast(
        ::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo - 1
    _bit_interp_eligible(v, x, lo, hi, order) ||
        return searchsortedlast(BinaryBracket(), v, x; order = order)
    g = _bit_interp_guess_f64(v, x, lo, hi, order)
    return searchsortedlast(BracketGallop(), v, x, g; order = order)
end

function Base.searchsortedfirst(
        ::BitInterpolationSearch, v::DenseVector{Float64}, x::Float64;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    lo, hi = firstindex(v), lastindex(v)
    hi < lo && return lo
    _bit_interp_eligible(v, x, lo, hi, order) ||
        return searchsortedfirst(BinaryBracket(), v, x; order = order)
    g = _bit_interp_guess_f64(v, x, lo, hi, order)
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

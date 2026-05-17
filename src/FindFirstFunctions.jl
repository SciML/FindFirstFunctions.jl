module FindFirstFunctions

# https://github.com/JuliaLang/julia/pull/53687
const USE_PTR = VERSION >= v"1.12.0-DEV.255"
const FFE_IR = """
declare i8 @llvm.cttz.i8(i8, i1);
define i64 @entry(i64 %0, $(USE_PTR ? "ptr" : "i64") %1, i64 %2) #0 {
top:
  $(USE_PTR ? "" : "%ivars = inttoptr i64 %1 to i64*")
  %btmp = insertelement <8 x i64> undef, i64 %0, i64 0
  %var = shufflevector <8 x i64> %btmp, <8 x i64> undef, <8 x i32> zeroinitializer
  %lenm7 = add nsw i64 %2, -7
  %dosimditer = icmp ugt i64 %2, 7
  br i1 %dosimditer, label %L9.lr.ph, label %L32

L9.lr.ph:
  %len8 = and i64 %2, 9223372036854775800
  br label %L9

L9:
  %i = phi i64 [ 0, %L9.lr.ph ], [ %vinc, %L30 ]
  %ivarsi = getelementptr inbounds i64, $(USE_PTR ? "ptr %1" : "i64* %ivars"), i64 %i
  $(USE_PTR ? "" : "%vpvi = bitcast i64* %ivarsi to <8 x i64>*")
  %v = load <8 x i64>, $(USE_PTR ? "ptr %ivarsi" : "<8 x i64> * %vpvi"), align 8
  %m = icmp eq <8 x i64> %v, %var
  %mu = bitcast <8 x i1> %m to i8
  %matchnotfound = icmp eq i8 %mu, 0
  br i1 %matchnotfound, label %L30, label %L17

L17:
  %tz8 = call i8 @llvm.cttz.i8(i8 %mu, i1 true)
  %tz64 = zext i8 %tz8 to i64
  %vis = add nuw i64 %i, %tz64
  br label %common.ret

common.ret:
  %retval = phi i64 [ %vis, %L17 ], [ -1, %L32 ], [ %si, %L51 ], [ -1, %L67 ]
  ret i64 %retval

L30:
  %vinc = add nuw nsw i64 %i, 8
  %continue = icmp slt i64 %vinc, %lenm7
  br i1 %continue, label %L9, label %L32

L32:
  %cumi = phi i64 [ 0, %top ], [ %len8, %L30 ]
  %done = icmp eq i64 %cumi, %2
  br i1 %done, label %common.ret, label %L51

L51:
  %si = phi i64 [ %inc, %L67 ], [ %cumi, %L32 ]
  %spi = getelementptr inbounds i64, $(USE_PTR ? "ptr %1" : "i64* %ivars"), i64 %si
  %svi = load i64, $(USE_PTR ? "ptr" : "i64*") %spi, align 8
  %match = icmp eq i64 %svi, %0
  br i1 %match, label %common.ret, label %L67

L67:
  %inc = add i64 %si, 1
  %dobreak = icmp eq i64 %inc, %2
  br i1 %dobreak, label %common.ret, label %L51

}
attributes #0 = { alwaysinline }
"""

function _findfirstequal(vpivot::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (FFE_IR, "entry"),
        Int64,
        Tuple{Int64, Ptr{Int64}, Int64},
        vpivot,
        ptr,
        len
    )
end

"""
    findfirstequal(x::Int64,A::DenseVector{Int64})

Finds the first index in `A` where the value equals `x`.
"""
findfirstequal(vpivot, ivars) = findfirst(isequal(vpivot), ivars)
function findfirstequal(vpivot::Int64, ivars::DenseVector{Int64})
    GC.@preserve ivars begin
        ret = _findfirstequal(vpivot, pointer(ivars), length(ivars))
    end
    return ret < 0 ? nothing : ret + 1
end

"""
findfirstsortedequal(vars::DenseVector{Int64}, var::Int64)::Union{Int64,Nothing}

Note that this differs from `searchsortedfirst` by returning `nothing` when absent.
"""
function findfirstsortedequal(
        var::Int64,
        vars::DenseVector{Int64},
        ::Val{basecase} = Base.libllvm_version >= v"17" ? Val(8) : Val(128)
    ) where {basecase}
    len = length(vars)
    offset = 0
    @inbounds while len > basecase
        half = len >>> 1 # half on left, len - half on right
        if Base.libllvm_version >= v"17"
            # TODO: check if this works
            # I'm worried the `!unpredictable` metadata will be stripped
            offset = Base.llvmcall(
                (
                    """
                                         define i64 @entry(i8 %0, i64 %1, i64 %2) #0 {
                                         top:
                                             %b = trunc i8 %0 to i1
                                             %s = select i1 %b, i64 %1, i64 %2, !unpredictable !0
                                             ret i64 %s
                                         }
                                         attributes #0 = { alwaysinline }
                                         !0 = !{}
                    """,
                    "entry",
                ),
                Int64,
                Tuple{Bool, Int64, Int64},
                vars[offset + half + 1] <= var,
                half + offset,
                offset
            )
        else
            offset = ifelse(vars[offset + half + 1] <= var, half + offset, offset)
        end
        len = len - half
    end
    # maybe occurs in vars[offset+1:offset+len]
    GC.@preserve vars begin
        ret = _findfirstequal(var, pointer(vars) + 8offset, len)
    end
    # return ret
    return ret < 0 ? nothing : ret + offset + 1
end

"""
    bracketstrictlymontonic(v, x, guess; lt=<comparison>, by=<transform>, rev=false)

Starting from an initial `guess` index, find indices `(lo, hi)` such that `v[lo] ≤ x ≤ v[hi]` according to the specified order, assuming that `x` is actually within the range of
values found in `v`.  If `x` is outside that range, either `lo` will be `firstindex(v)` or
`hi` will be `lastindex(v)`.

Note that the results will not typically satisfy `lo ≤ guess ≤ hi`.  If `x` is precisely
equal to a value that is not unique in the input `v`, there is no guarantee that `(lo, hi)`
will encompass *all* indices corresponding to that value.

This algorithm is essentially an expanding binary search, which can be used as a precursor
to `searchsorted` and related functions, which can take `lo` and `hi` as arguments.  The
purpose of using this function first would be to accelerate convergence in those functions
by using correlated `guess`es for repeated calls.  The best `guess` for the next call of
this function would be the index returned by the previous call to `searchsorted`.

See `Base.sort!` for an explanation of the keyword arguments `by`, `lt` and `rev`.
"""
function bracketstrictlymontonic(
        v::AbstractVector,
        x,
        guess::T,
        o::Base.Order.Ordering
    )::NTuple{2, keytype(v)} where {T <: Integer}
    bottom = firstindex(v)
    top = lastindex(v)
    if guess < bottom || guess > top
        return bottom, top
        # # NOTE: for cache efficiency in repeated calls, we avoid accessing the first and last elements of `v`
        # # on each call to this function.  This should only result in significant slow downs for calls with
        # # out-of-bounds values of `x` *and* bad `guess`es.
        # elseif lt(o, x, v[bottom])
        #     return bottom, bottom
        # elseif lt(o, v[top], x)
        #     return top, top
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

# ---------------------------------------------------------------------------
# Sorted-search strategies
# ---------------------------------------------------------------------------

"""
    SearchStrategy

Abstract supertype for sorted-search strategies. Concrete subtypes select how
[`searchsortedlast`](@ref Base.searchsortedlast) and
[`searchsortedfirst`](@ref Base.searchsortedfirst) should be performed when
called with a strategy as the first positional argument:

  - [`LinearScan`](@ref) walks ±1 from the hint. Cheapest when the target is
    within a few positions of the hint; degrades linearly otherwise.
  - [`BracketGallop`](@ref) expands an exponential bracket bidirectionally
    from the hint, then binary-searches inside it. Effectively O(1) when the
    target is near the hint; never worse than ~2 log₂ n comparisons. This is
    the strategy used by the legacy [`searchsortedfirstcorrelated`](@ref) /
    [`searchsortedlastcorrelated`](@ref).
  - [`ExpFromLeft`](@ref) expands rightward from a left-bound hint by
    doubling, then binary-searches inside the final bracket. Best for batched
    sorted queries where each next query's hint is the previous result.
  - [`InterpolationSearch`](@ref) guesses the answer by linearly extrapolating
    between `v[lo]` and `v[hi]`, then refines with a bounded binary search.
    O(1) per query on uniformly-spaced data; falls back to O(log n) on
    irregular data.
  - [`BinaryBracket`](@ref) is the standard `Base.searchsortedlast` /
    `Base.searchsortedfirst` with no hint. Use it when no useful hint exists.
  - [`Auto`](@ref) heuristically picks one of the above based on the size of
    `v`, the spacing of `v`, and whether a hint was supplied.

Strategies can also be passed to the batched
[`searchsortedlast!`](@ref) / [`searchsortedfirst!`](@ref) APIs.
"""
abstract type SearchStrategy end

"""
    LinearScan <: SearchStrategy

Walk ±1 from the hint. Best when the target is within a few positions of the
hint. Falls back to [`BinaryBracket`](@ref) when no hint is supplied.
"""
struct LinearScan <: SearchStrategy end

"""
    BracketGallop <: SearchStrategy

Expand an exponential bracket from the hint using
[`bracketstrictlymontonic`](@ref), then binary-search inside the bracket. The
default strategy backing [`searchsortedfirstcorrelated`](@ref) and
[`searchsortedlastcorrelated`](@ref). Falls back to [`BinaryBracket`](@ref)
when no hint is supplied.
"""
struct BracketGallop <: SearchStrategy end

"""
    ExpFromLeft <: SearchStrategy

Exponential search forward from the hint (interpreted as a left bound), then
binary search in the final bracket. The hint is a *lower* bound rather than a
center guess, which is what batched sorted-search loops typically want:
`hint = previous_result`.

Specifically: starting at `lo = hint`, check `v[lo], v[lo+1], ..., v[lo+4]`
linearly, then `v[lo+8], v[lo+16], …` exponentially, until `x` is bracketed,
then binary-search inside the bracket. Same algorithm as the standalone
[`searchsortedfirstexp`](@ref), wrapped here as a dispatchable strategy.

Falls back to [`BinaryBracket`](@ref) when no hint is supplied.
"""
struct ExpFromLeft <: SearchStrategy end

"""
    InterpolationSearch <: SearchStrategy

Guesses an index by linearly extrapolating `x` between `v[lo]` and `v[hi]`,
then refines with a bounded binary search. O(1) per query on uniformly-spaced
data (e.g. `collect(0:0.1:10)`); falls back to O(log n) otherwise. Requires
`x` to be subtractable with elements of `v` (i.e., a numeric ordering).

Ignores any hint that is supplied — the guess is computed fresh from the
endpoints. Falls back to [`BinaryBracket`](@ref) for non-numeric element
types where subtraction isn't defined.
"""
struct InterpolationSearch <: SearchStrategy end

"""
    BinaryBracket <: SearchStrategy

Plain `Base.searchsortedlast` / `Base.searchsortedfirst`. Ignores any hint
that is supplied.
"""
struct BinaryBracket <: SearchStrategy end

"""
    GuesserHint(guesser::Guesser) <: SearchStrategy

Uses a [`Guesser`](@ref) to produce an integer guess for `x`, then dispatches
to [`BracketGallop`](@ref) from that guess. The `Guesser` already decides
between linear-extrapolation lookup (when `v` looks linear) and using the
previous result as a guess; this strategy plugs that logic into the strategy
dispatch hierarchy, and updates `guesser.idx_prev` on each call.

This is the strategy backing the existing
`searchsortedfirstcorrelated(v, x, ::Guesser)` and
`searchsortedlastcorrelated(v, x, ::Guesser)` overloads, exposed so it can
be passed to the batched [`searchsortedlast!`](@ref) / [`searchsortedfirst!`](@ref)
APIs.
"""
struct GuesserHint{G} <: SearchStrategy
    guesser::G
end

"""
    Auto <: SearchStrategy

Heuristically picks among [`LinearScan`](@ref), [`ExpFromLeft`](@ref),
[`BracketGallop`](@ref), and [`BinaryBracket`](@ref). The choice depends on
the calling context:

**Per-query** (`searchsortedlast(Auto(), v, x[, hint])`):
  - No hint, or hint outside `axes(v)` → [`BinaryBracket`](@ref).
  - Hint in range, `length(v) ≤ 16` → [`LinearScan`](@ref).
  - Hint in range, `length(v) > 16` → [`BracketGallop`](@ref).

**Batched sorted** (`searchsortedlast!(out, v, queries; strategy = Auto())`),
using the expected average gap between consecutive results. For numeric
data the gap is estimated from the span ratio
`(queries[end] - queries[1]) / (v[end] - v[1])` so that dense-burst queries
clustered inside one segment of `v` are recognized as having gap ≈ 0:
  - `gap ≤ 4` → [`LinearScan`](@ref) (most queries land in the same
    segment or the next; linear-walk overhead is minimal, and `ExpFromLeft`
    wastes its 5 initial linear probes when the gap is already 0 or 1).
  - `gap > 64`, `length(v) ≥ 1024`, `length(queries) ≥ 2`, and a sampled
    linearity probe (5 reads, ~12 ns) accepts → [`InterpolationSearch`](@ref).
    On uniformly-spaced data this is ~2× faster than `ExpFromLeft` for
    sparse queries; the linearity probe is what keeps `Auto` from picking
    `InterpolationSearch` on irregular data where it would lose badly.
  - otherwise → [`ExpFromLeft`](@ref) (linear probes for very small
    jumps, doubling for medium, bounded binary search for far — always
    moving forward from the previous result, which is what
    `BracketGallop`'s bidirectional bracketing wastes effort on).

**Batched unsorted**: falls back to per-element `Base.searchsortedlast` /
`Base.searchsortedfirst` with no hint regardless of strategy.
"""
struct Auto <: SearchStrategy end

# Per-query Auto threshold: under this length, the bracket-search bookkeeping
# costs more than a worst-case linear walk.
const _AUTO_LINEAR_THRESHOLD = 16

# Batched-Auto crossover: at gap ≤ 4 LinearScan beats ExpFromLeft (its 5
# initial linear probes are wasted when the gap is already 0 or 1).
# Above 4, ExpFromLeft handles arbitrary gap sizes via doubling — the
# bench sweep shows it strictly beats BracketGallop for forward-moving
# sorted queries.
const _AUTO_BATCH_LINEAR_GAP = 4

# For sparse queries (gap large) on long vectors, InterpolationSearch can
# beat ExpFromLeft by ~2× on uniformly-spaced data. The sampled-linearity
# check below is O(1) — 5 fixed probes — so it's cheap enough to run inside
# Auto when there's a real chance of unlocking InterpolationSearch.
const _AUTO_INTERP_MIN_GAP = 8
const _AUTO_INTERP_MIN_N = 1024
const _AUTO_INTERP_MIN_M = 2
const _AUTO_LINEAR_REL_TOLERANCE = 1.0e-3

# Sampled linearity check: probes v[1], v[k*n/10] for k = 1..9, v[n] and
# tests whether all interior points sit within `_AUTO_LINEAR_REL_TOLERANCE`
# (default 0.1%) of the straight line between v[1] and v[n]. The tight
# tolerance reliably distinguishes truly-uniform data from random/sorted
# data even at large n (where the order-statistic variance ≈ 1/sqrt(n)
# would fool a looser check).
#
# Cost is ~25 ns regardless of n — 11 reads + 9 comparisons. Used by Auto
# to decide whether to gamble on InterpolationSearch.
#
# InterpolationSearch's downside on non-linear data is large (4-14× slower
# than ExpFromLeft on log/plateau/two-scale spacings), so we err on the
# side of rejecting borderline cases. Truly uniform data — exact ranges,
# evenly-spaced grids, and small-amplitude jittered data — passes; sorted
# random data is rejected at all `n` tested up to ~10⁶.
@inline function _sampled_looks_linear(v::AbstractVector{<:Number})
    n = length(v)
    n < 11 && return false
    @inbounds begin
        v1, vn = v[1], v[n]
        span = vn - v1
        (iszero(span) || !isfinite(span)) && return false
        abs_span = abs(span)
        nm1 = n - 1
        for k in 1:9
            kk = 1 + (k * nm1) ÷ 10
            expected = v1 + (kk - 1) / nm1 * span
            rel_err = abs(v[kk] - expected) / abs_span
            rel_err > _AUTO_LINEAR_REL_TOLERANCE && return false
        end
    end
    return true
end

# Non-numeric eltype: can't sample, never picks InterpolationSearch.
@inline _sampled_looks_linear(::AbstractVector) = false

# AbstractRange is definitionally uniform — accept without sampling.
@inline _sampled_looks_linear(::AbstractRange) = true

# Strategy: BinaryBracket — ignore any hint.
Base.searchsortedlast(
    ::BinaryBracket, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(v, x, order)
Base.searchsortedfirst(
    ::BinaryBracket, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(v, x, order)
Base.searchsortedlast(
    s::BinaryBracket, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::BinaryBracket, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(s, v, x; order = order)

# Strategy: LinearScan — walk ±1 from the hint until the answer is bracketed.
function Base.searchsortedlast(
        ::LinearScan, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
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
        order::Base.Order.Ordering = Base.Order.Forward
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
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::LinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# Strategy: BracketGallop — bracketstrictlymontonic + bounded binary search.
function Base.searchsortedlast(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    lo, hi = bracketstrictlymontonic(v, x, hint, order)
    return searchsortedlast(v, x, lo, hi, order)
end

function Base.searchsortedfirst(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    lo, hi = bracketstrictlymontonic(v, x, hint, order)
    return searchsortedfirst(v, x, lo, hi, order)
end

# BracketGallop without a hint falls back to BinaryBracket.
Base.searchsortedlast(
    ::BracketGallop, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::BracketGallop, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# Strategy: ExpFromLeft — galloping forward from a left-bound hint.
#
# Contract: callers pass `hint` such that the answer is ≥ `hint`. When that
# isn't true (hint is past the answer), we fall back to a full
# `searchsortedlast`/`searchsortedfirst` — the batched-sorted loop sets
# `hint = prev_result`, which always satisfies this for sorted queries, so the
# fallback is only exercised by arbitrary single-query callers.
function Base.searchsortedfirst(
        ::ExpFromLeft, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    lo = firstindex(v)
    hi = lastindex(v)
    if isempty(v)
        return lo
    end
    h = clamp(hint, lo, hi)
    @inbounds if Base.Order.lt(order, x, v[h])
        # x < v[hint] → hint is past the answer; full search.
        return searchsortedfirst(v, x, order)
    end
    return order === Base.Order.Forward ?
        searchsortedfirstexp(v, x, h, hi) :
        searchsortedfirst(v, x, h, hi, order)
end

function Base.searchsortedlast(
        ::ExpFromLeft, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
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
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::ExpFromLeft, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# Strategy: InterpolationSearch — extrapolate a guess, then bounded binary search.
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
        order::Base.Order.Ordering = Base.Order.Forward
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
        order::Base.Order.Ordering = Base.Order.Forward
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
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::InterpolationSearch, v::AbstractVector{<:Number}, x::Number, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(s, v, x; order = order)

# InterpolationSearch on non-numeric data falls back to BinaryBracket.
Base.searchsortedlast(
    ::InterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::InterpolationSearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)
Base.searchsortedlast(
    s::InterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::InterpolationSearch, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# Strategy: GuesserHint — Guesser produces an integer hint, BracketGallop runs
# the search and updates the Guesser's prev-result cache. Methods are defined
# below where Guesser is in scope (search the file for "GuesserHint methods").

# Strategy: Auto — pick based on hint validity and length(v).
@inline function _auto_pick(v::AbstractVector, hint::Integer)
    return if hint < firstindex(v) || hint > lastindex(v)
        BinaryBracket()
    elseif length(v) <= _AUTO_LINEAR_THRESHOLD
        LinearScan()
    else
        BracketGallop()
    end
end

# Batched Auto: pick based on the expected average gap between consecutive
# results.
#
# For numeric data we can do better than `n / m`: the queries' actual span as
# a fraction of `v`'s span tells us how clustered they really are. e.g.
# 4096 sorted queries crammed into a single segment of a 65k-long `v` have
# n/m = 16 but actual_gap = 0; the span heuristic catches that.
@inline function _auto_pick_batched(v::AbstractVector, queries::AbstractVector)
    m = length(queries)
    if m == 0
        return BinaryBracket()
    end
    gap, _ = _estimate_avg_gap(v, queries, m)
    return gap <= _AUTO_BATCH_LINEAR_GAP ? LinearScan() : ExpFromLeft()
end

# Returns `(gap, skewed)`: the estimated average step in `v`'s index space
# between consecutive query results, plus a flag that's true when the
# queries' distribution is non-uniform within their span. The skew flag is
# what lets Auto reject InterpolationSearch even when the gap is large:
# `ExpFromLeft` from `prev_idx` wins on skewed queries because consecutive
# queries land in the same neighbourhood, regardless of `v` being linear.
@inline function _estimate_avg_gap(
        v::AbstractVector{<:Number}, queries::AbstractVector{<:Number}, m::Integer
    )
    n = length(v)
    n <= 1 && return (0, false)
    @inbounds span_v = v[end] - v[1]
    if iszero(span_v) || !isfinite(span_v)
        return (n ÷ max(1, m), false)
    end
    @inbounds span_q = queries[end] - queries[1]
    # Skew detection on small `m` is too noisy — for `m ≈ 4` random uniform
    # samples, the median routinely sits 30 %+ off the linear midpoint by
    # chance. Gate on `m ≥ 10` where the statistical variance is well below
    # the 20 % threshold.
    skewed = false
    if m >= 10
        @inbounds mid_q = queries[firstindex(queries) + m ÷ 2]
        @inbounds expected_mid = (
            queries[firstindex(queries)] +
                queries[lastindex(queries)]
        ) / 2
        if !iszero(span_q) &&
                abs(mid_q - expected_mid) > 0.2 * abs(span_q)
            skewed = true
        end
    end
    if skewed
        return (n ÷ max(1, m), true)
    end
    ratio = span_q / span_v
    # Clamp ratio: queries may extend outside v's range (extrapolation).
    ratio = clamp(ratio, zero(ratio), one(ratio))
    return (floor(Int, n * ratio / max(1, m)), false)
end

# Non-numeric eltypes: no span subtraction possible, fall back to length ratio
# and assume queries are roughly uniform (no skew detection possible).
@inline _estimate_avg_gap(
    v::AbstractVector, ::AbstractVector, m::Integer
) = (length(v) ÷ max(1, m), false)

function Base.searchsortedlast(
        ::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    s = _auto_pick(v, hint)
    return s isa BinaryBracket ?
        searchsortedlast(s, v, x; order = order) :
        searchsortedlast(s, v, x, hint; order = order)
end

function Base.searchsortedfirst(
        ::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    s = _auto_pick(v, hint)
    return s isa BinaryBracket ?
        searchsortedfirst(s, v, x; order = order) :
        searchsortedfirst(s, v, x, hint; order = order)
end

Base.searchsortedlast(
    ::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# ---------------------------------------------------------------------------
# In-place batched sorted-search API
# ---------------------------------------------------------------------------

"""
    searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)

In-place batched [`searchsortedlast`](@ref Base.searchsortedlast). Writes one
index per element of `queries` into `idx_out` (which must be the same length).

If `queries` is sorted under `order`, the previous result is used as a hint for
the next query, so the total cost is O(length(v) + length(queries)) under
`strategy = BracketGallop()` (the default `Auto` choice for non-tiny `v`),
matching what callers used to hand-roll with `searchsortedlastcorrelated` +
a manually-maintained `idx` variable.

If `queries` is not sorted, falls back to per-element `searchsortedlast` with
no hint regardless of `strategy`.

Returns `idx_out`.
"""
function searchsortedlast!(
        idx_out::AbstractVector{<:Integer},
        v::AbstractVector,
        queries::AbstractVector;
        strategy::SearchStrategy = Auto(),
        order::Base.Order.Ordering = Base.Order.Forward
    )
    if length(idx_out) != length(queries)
        throw(
            DimensionMismatch(
                "idx_out and queries must have the same length"
            )
        )
    end
    return _searchsortedlast_batched!(idx_out, v, queries, strategy, order)
end

"""
    searchsortedfirst!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward)

In-place batched [`searchsortedfirst`](@ref Base.searchsortedfirst). See
[`searchsortedlast!`](@ref) for behavior.
"""
function searchsortedfirst!(
        idx_out::AbstractVector{<:Integer},
        v::AbstractVector,
        queries::AbstractVector;
        strategy::SearchStrategy = Auto(),
        order::Base.Order.Ordering = Base.Order.Forward
    )
    if length(idx_out) != length(queries)
        throw(
            DimensionMismatch(
                "idx_out and queries must have the same length"
            )
        )
    end
    return _searchsortedfirst_batched!(idx_out, v, queries, strategy, order)
end

# Sorted inner loop, parameterized on strategy. Used by both the generic and
# Auto batched entry points so each batch performs at most one issorted check.
function _searchsortedlast_sorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering
    )
    hint = firstindex(v) - 1
    @inbounds for k in eachindex(queries)
        q = queries[k]
        hint = if hint < firstindex(v)
            searchsortedlast(strategy, v, q; order = order)
        else
            searchsortedlast(strategy, v, q, hint; order = order)
        end
        idx_out[k] = hint
    end
    return idx_out
end

function _searchsortedfirst_sorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering
    )
    hint = firstindex(v) - 1
    @inbounds for k in eachindex(queries)
        q = queries[k]
        hint = if hint < firstindex(v)
            searchsortedfirst(strategy, v, q; order = order)
        else
            searchsortedfirst(strategy, v, q, hint; order = order)
        end
        idx_out[k] = hint
    end
    return idx_out
end

function _searchsortedlast_unsorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        order::Base.Order.Ordering
    )
    @inbounds for k in eachindex(queries)
        idx_out[k] = searchsortedlast(v, queries[k], order)
    end
    return idx_out
end

function _searchsortedfirst_unsorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        order::Base.Order.Ordering
    )
    @inbounds for k in eachindex(queries)
        idx_out[k] = searchsortedfirst(v, queries[k], order)
    end
    return idx_out
end

function _searchsortedlast_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering
    )
    return if issorted(queries; order = order)
        _searchsortedlast_sorted_loop!(idx_out, v, queries, strategy, order)
    else
        _searchsortedlast_unsorted_loop!(idx_out, v, queries, order)
    end
end

# Specialized batched-Auto: pick an inner strategy from the n/m ratio, then
# call the sorted loop directly (no duplicate `issorted` check, and each
# branch is type-stable so the loop specializes on the concrete strategy).
function _searchsortedlast_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        ::Auto, order::Base.Order.Ordering
    )
    m = length(queries)
    m == 0 && return idx_out
    # m == 1: skip the issorted + span heuristic — no batched hint is
    # available for a single-element batch, so just dispatch straight to
    # the unhinted backing call. Saves ~20 ns of bookkeeping per call.
    if m == 1
        @inbounds idx_out[firstindex(idx_out)] =
            searchsortedlast(v, queries[firstindex(queries)], order)
        return idx_out
    end
    if !issorted(queries; order = order)
        return _searchsortedlast_unsorted_loop!(idx_out, v, queries, order)
    end
    gap, skewed = _estimate_avg_gap(v, queries, m)
    # Manually dispatch on the picked strategy so each branch is concrete.
    if gap <= _AUTO_BATCH_LINEAR_GAP
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, LinearScan(), order
        )
    end
    # Sparse-on-large-linear: InterpolationSearch wins ~2× over ExpFromLeft
    # on uniformly-spaced data — but only when queries are *also* spread
    # roughly uniformly within their span. For skewed (clustered) queries,
    # `ExpFromLeft` from `prev_idx` wins even on linear v because the next
    # query's true index is close to the previous one's.
    if !skewed &&
            gap >= _AUTO_INTERP_MIN_GAP &&
            length(v) >= _AUTO_INTERP_MIN_N &&
            m >= _AUTO_INTERP_MIN_M &&
            _sampled_looks_linear(v)
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, InterpolationSearch(), order
        )
    end
    return _searchsortedlast_sorted_loop!(
        idx_out, v, queries, ExpFromLeft(), order
    )
end

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering
    )
    return if issorted(queries; order = order)
        _searchsortedfirst_sorted_loop!(idx_out, v, queries, strategy, order)
    else
        _searchsortedfirst_unsorted_loop!(idx_out, v, queries, order)
    end
end

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        ::Auto, order::Base.Order.Ordering
    )
    m = length(queries)
    m == 0 && return idx_out
    if m == 1
        @inbounds idx_out[firstindex(idx_out)] =
            searchsortedfirst(v, queries[firstindex(queries)], order)
        return idx_out
    end
    if !issorted(queries; order = order)
        return _searchsortedfirst_unsorted_loop!(idx_out, v, queries, order)
    end
    gap, skewed = _estimate_avg_gap(v, queries, m)
    if gap <= _AUTO_BATCH_LINEAR_GAP
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, LinearScan(), order
        )
    end
    if !skewed &&
            gap >= _AUTO_INTERP_MIN_GAP &&
            length(v) >= _AUTO_INTERP_MIN_N &&
            m >= _AUTO_INTERP_MIN_M &&
            _sampled_looks_linear(v)
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, InterpolationSearch(), order
        )
    end
    return _searchsortedfirst_sorted_loop!(
        idx_out, v, queries, ExpFromLeft(), order
    )
end

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

Wrapper of the searched vector `v` which makes an informed guess
for `searchsorted*correlated` by either

  - Exploiting that `v` is sufficiently evenly spaced
  - Using the previous outcome of `searchsorted*correlated`
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

"""
    searchsortedfirstcorrelated(v::AbstractVector, x, guess; order=Base.Order.Forward)

An accelerated `findfirst` on sorted vectors using a bracketed search. Requires a `guess::Union{<:Integer, Guesser}`
to start the search from.

The `order` keyword argument specifies the ordering of the vector `v`, defaulting to `Base.Order.Forward`.

Equivalent to `searchsortedfirst(BracketGallop(), v, x, guess; order = order)`.
"""
function searchsortedfirstcorrelated(
        v::AbstractVector,
        x,
        guess::T;
        order::Base.Order.Ordering = Base.Order.Forward
    ) where {T <: Integer}
    return searchsortedfirst(BracketGallop(), v, x, guess; order = order)
end

"""
    searchsortedlastcorrelated(v::AbstractVector{T}, x, guess; order=Base.Order.Forward)

An accelerated `findlast` on sorted vectors using a bracketed search. Requires a `guess::Union{<:Integer, Guesser}`
to start the search from.

The `order` keyword argument specifies the ordering of the vector `v`, defaulting to `Base.Order.Forward`.

Equivalent to `searchsortedlast(BracketGallop(), v, x, guess; order = order)`.
"""
function searchsortedlastcorrelated(
        v::AbstractVector,
        x,
        guess::T;
        order::Base.Order.Ordering = Base.Order.Forward
    ) where {T <: Integer}
    return searchsortedlast(BracketGallop(), v, x, guess; order = order)
end

searchsortedfirstcorrelated(r::AbstractRange, x, ::Integer) = searchsortedfirst(r, x)
searchsortedlastcorrelated(r::AbstractRange, x, ::Integer) = searchsortedlast(r, x)

function searchsortedfirstcorrelated(
        v::AbstractVector,
        x,
        guess::Guesser{T};
        order::Base.Order.Ordering = Base.Order.Forward
    ) where {T <: AbstractVector}
    @assert v === guess.v
    out = searchsortedfirstcorrelated(v, x, guess(x); order = order)
    guess.idx_prev[] = out
    return out
end

function searchsortedlastcorrelated(
        v::T,
        x,
        guess::Guesser{T};
        order::Base.Order.Ordering = Base.Order.Forward
    ) where {T <: AbstractVector}
    @assert v === guess.v
    out = searchsortedlastcorrelated(v, x, guess(x); order = order)
    guess.idx_prev[] = out
    return out
end

# GuesserHint methods — strategy dispatch wrapper for the `Guesser`-based
# correlated search. Per-call cost: one `guesser(x)` evaluation + one
# `BracketGallop` call + one `idx_prev[]` write.
function Base.searchsortedlast(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    @assert v === s.guesser.v
    out = searchsortedlast(BracketGallop(), v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

function Base.searchsortedfirst(
        s::GuesserHint, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    @assert v === s.guesser.v
    out = searchsortedfirst(BracketGallop(), v, x, s.guesser(x); order = order)
    s.guesser.idx_prev[] = out
    return out
end

# GuesserHint ignores any externally-supplied hint (the Guesser carries its own).
Base.searchsortedlast(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(s, v, x; order = order)
Base.searchsortedfirst(
    s::GuesserHint, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(s, v, x; order = order)

"""
    searchsortedfirstexp(v, x, lo=firstindex(v), hi=lastindex(v))

Find the first index `i` in sorted vector `v` such that `v[i] >= x`, starting from `lo`.
This uses an exponential search followed by binary search, which is efficient when
the target is expected to be near `lo` (e.g., for correlated sequential lookups).

Inspired by Interpolations.jl's `searchsortedfirst_exp_left`.
"""
Base.@propagate_inbounds function searchsortedfirstexp(
        v::AbstractVector,
        x,
        lo::Integer = firstindex(v),
        hi::Integer = lastindex(v)
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

"""
    searchsortedlastvec(v::AbstractVector, x::AbstractVector)

Find the indices for multiple sorted values `x` in sorted vector `v` efficiently.
If `x` is sorted, this leverages monotonicity to avoid redundant searching.
Returns indices such that `v[out[i]] <= x[i]` (like `searchsortedlast`).

If `x` is not sorted, falls back to element-wise `searchsortedlast`.

Allocating wrapper around [`searchsortedlast!`](@ref) with the default `Auto`
strategy. Inspired by Interpolations.jl's `searchsortedfirst_vec`.
"""
function searchsortedlastvec(v::AbstractVector, x::AbstractVector)
    out = Vector{Int}(undef, length(x))
    return searchsortedlast!(out, v, x)
end

"""
    searchsortedfirstvec(v::AbstractVector, x::AbstractVector)

Find the indices for multiple sorted values `x` in sorted vector `v` efficiently.
If `x` is sorted, this leverages monotonicity to avoid redundant searching.
Returns indices such that `v[out[i]] >= x[i]` (like `searchsortedfirst`).

If `x` is not sorted, falls back to element-wise `searchsortedfirst`.

Allocating wrapper around [`searchsortedfirst!`](@ref) with the default `Auto`
strategy. Inspired by Interpolations.jl's `searchsortedfirst_vec`.
"""
function searchsortedfirstvec(v::AbstractVector, x::AbstractVector)
    out = Vector{Int}(undef, length(x))
    return searchsortedfirst!(out, v, x)
end

using PrecompileTools: @compile_workload, @setup_workload

@setup_workload begin
    # Minimal setup for precompilation workload
    vec_int64 = Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    linear_vec = collect(1.0:0.5:10.0)

    @compile_workload begin
        # Precompile the most commonly used functions with typical types

        # findfirstequal: fast SIMD-based search in Int64 vectors
        findfirstequal(Int64(5), vec_int64)
        findfirstequal(Int64(100), vec_int64)  # not found case

        # findfirstsortedequal: binary search in sorted Int64 vectors
        findfirstsortedequal(Int64(8), vec_int64)
        findfirstsortedequal(Int64(100), vec_int64)  # not found case

        # bracketstrictlymontonic: bracketing for sorted vectors
        bracketstrictlymontonic(vec_int64, Int64(8), Int64(1), Base.Order.Forward)

        # looks_linear: check if vector is evenly spaced
        looks_linear(linear_vec)

        # Guesser: wrapper for efficient repeated searches
        guesser = Guesser(linear_vec)
        guesser(5.0)

        # searchsortedfirstcorrelated and searchsortedlastcorrelated
        searchsortedfirstcorrelated(vec_int64, Int64(8), Int64(1))
        searchsortedlastcorrelated(vec_int64, Int64(8), Int64(1))

        # Also precompile with Guesser
        guesser_int = Guesser(vec_int64)
        searchsortedfirstcorrelated(vec_int64, Int64(8), guesser_int)
        searchsortedlastcorrelated(vec_int64, Int64(8), guesser_int)
    end
end

end # module FindFirstFunctions

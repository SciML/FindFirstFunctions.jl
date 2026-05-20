module FindFirstFunctions

# Public API surface for `using FindFirstFunctions`. The strategy types are
# zero-field singletons (except `GuesserHint` and `Auto`, which carry small
# isbits payloads), so exporting them only adds names to the caller's
# namespace — no runtime cost. `searchsortedfirst!` / `searchsortedlast!`
# are FFF-defined names (the non-bang `searchsortedfirst` /
# `searchsortedlast` are extensions of `Base` and are reachable without
# qualification once `Base` is in scope).
export
    SearchStrategy,
    LinearScan, SIMDLinearScan, BracketGallop, ExpFromLeft,
    InterpolationSearch, BinaryBracket, BisectThenSIMD,
    GuesserHint, Auto,
    SearchProperties,
    Guesser, looks_linear,
    searchsortedfirst!, searchsortedlast!,
    findequal, findfirstequal, findfirstsortedequal

# https://github.com/JuliaLang/julia/pull/53687
const USE_PTR = VERSION >= v"1.12.0-DEV.255"

# Generate the SIMD "find first lane matching predicate" IR for an arbitrary
# scalar type and LLVM compare predicate. Load 8 lanes at a time, compare
# against a broadcast of the search value, bitcast the i1×8 mask to i8,
# `cttz` to find the first set bit. The tail past the last full chunk is
# handled scalar-wise.
#
# Used to back four equality / inequality SIMD primitives:
#   - `_findfirstequal`        — exact equality, Int64 (predicate `eq`)
#   - `_simd_first_gt`/`_ge`   — strict / non-strict greater-than, Int64
#                                 (predicates `sgt` / `sge`)
#   - same pair for Float64    — predicates `ogt` / `oge` (ordered compares)
function _simd_scan_ir(t, pred)
    cmp = pred[1] in ('o', 'u') ? "fcmp" : "icmp"
    return """
    declare i8 @llvm.cttz.i8(i8, i1);
    define i64 @entry($t %0, $(USE_PTR ? "ptr" : "i64") %1, i64 %2) #0 {
    top:
      $(USE_PTR ? "" : "%ivars = inttoptr i64 %1 to $t*")
      %btmp = insertelement <8 x $t> undef, $t %0, i64 0
      %var = shufflevector <8 x $t> %btmp, <8 x $t> undef, <8 x i32> zeroinitializer
      %lenm7 = add nsw i64 %2, -7
      %dosimditer = icmp ugt i64 %2, 7
      br i1 %dosimditer, label %L9.lr.ph, label %L32

    L9.lr.ph:
      %len8 = and i64 %2, 9223372036854775800
      br label %L9

    L9:
      %i = phi i64 [ 0, %L9.lr.ph ], [ %vinc, %L30 ]
      %ivarsi = getelementptr inbounds $t, $(USE_PTR ? "ptr %1" : "$t* %ivars"), i64 %i
      $(USE_PTR ? "" : "%vpvi = bitcast $t* %ivarsi to <8 x $t>*")
      %v = load <8 x $t>, $(USE_PTR ? "ptr %ivarsi" : "<8 x $t> * %vpvi"), align 8
      %m = $cmp $pred <8 x $t> %v, %var
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
      %spi = getelementptr inbounds $t, $(USE_PTR ? "ptr %1" : "$t* %ivars"), i64 %si
      %svi = load $t, $(USE_PTR ? "ptr" : "$t*") %spi, align 8
      %match = $cmp $pred $t %svi, %0
      br i1 %match, label %common.ret, label %L67

    L67:
      %inc = add i64 %si, 1
      %dobreak = icmp eq i64 %inc, %2
      br i1 %dobreak, label %common.ret, label %L51

    }
    attributes #0 = { alwaysinline }
    """
end

const FFE_IR = _simd_scan_ir("i64", "eq")

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
    findfirstequal(x, A) -> Union{Int, Nothing}

Find the first index in `A` where the value equals `x`. Returns `nothing`
if `x` does not occur in `A`.

This function does **not** assume `A` is sorted. For sorted vectors, see
[`findfirstsortedequal`](@ref) (a bisect-then-SIMD specialization on
`DenseVector{Int64}`) or [`findequal`](@ref) (the strategy-framework
equality wrapper that returns an `Int` with a sentinel).

The `(x::Int64, A::DenseVector{Int64})` method uses a custom LLVM IR SIMD
scan (load 8 lanes, `icmp eq`, `cttz` on the mask) — about 8× faster than
the scalar `findfirst(==(x), v)` on modern x86-64. Every other element-type
and array-storage combination falls back to `findfirst(isequal(x), A)`.
"""
findfirstequal(vpivot, ivars) = findfirst(isequal(vpivot), ivars)
function findfirstequal(vpivot::Int64, ivars::DenseVector{Int64})
    GC.@preserve ivars begin
        ret = _findfirstequal(vpivot, pointer(ivars), length(ivars))
    end
    return ret < 0 ? nothing : ret + 1
end

const _SIMD_GT_I64_IR = _simd_scan_ir("i64", "sgt")
const _SIMD_GE_I64_IR = _simd_scan_ir("i64", "sge")
const _SIMD_GT_F64_IR = _simd_scan_ir("double", "ogt")
const _SIMD_GE_F64_IR = _simd_scan_ir("double", "oge")

# Backing primitives for SIMDLinearScan. Each returns the 0-based offset of
# the first lane satisfying the predicate, or -1 if none. Caveat: NaN inputs
# always compare false under the ordered `o*` float predicates, so NaN in `v`
# or `x` produces "no match" rather than an exception — consistent with the
# undefined-input contract for sorted Float64 vectors containing NaN.
function _simd_first_gt(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GT_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_ge(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GE_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_gt(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GT_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end
function _simd_first_ge(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GE_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end

"""
    findfirstsortedequal(var::Int64, vars::DenseVector{Int64}) -> Union{Int64, Nothing}

Find the index of the first occurrence of `var` in the sorted vector
`vars`. Returns `nothing` if `var` does not occur. Specialized for
`DenseVector{Int64}` via a branchless binary bisection down to a small
basecase, followed by the same SIMD equality scan that backs
[`findfirstequal`](@ref) — faster than plain `findfirst(==(var), vars)`
or `searchsortedfirst` + post-check for typical Int64 vectors.

The strategy-framework equivalent is
[`findequal(BisectThenSIMD(), vars, var)`](@ref findequal); that wrapper
returns an `Int` with a sentinel (`firstindex(v) - 1`) for "not found",
which is type-stable and composes with the rest of the strategy
dispatch. Prefer `findequal` for new code; `findfirstsortedequal` remains
as the dedicated `Union{Int64, Nothing}`-returning name.
"""
function findfirstsortedequal(
        var::Int64,
        vars::DenseVector{Int64},
        ::Val{basecase} = Base.libllvm_version >= v"17" ? Val(8) : Val(128)
    ) where {basecase}
    len = length(vars)
    offset = 0
    @inbounds while len > basecase
        # Bisect with the predicate `vars[mid] < var` (strict). When true,
        # `var` is past the midpoint — drop the left half *and* the
        # midpoint itself. When false (`vars[mid] >= var`), `var` may be
        # at the midpoint, so keep `offset` and shrink the window to
        # `vars[offset+1 .. offset+half+1]` (inclusive of the midpoint).
        # The earlier `<=` predicate would have advanced past matching
        # midpoints, masking earlier duplicates of `var`.
        half = len >>> 1
        mid = offset + half + 1
        is_left_strictly_less = vars[mid] < var
        offset = ifelse(is_left_strictly_less, offset + half + 1, offset)
        len = ifelse(is_left_strictly_less, len - half - 1, half + 1)
    end
    # maybe occurs in vars[offset+1:offset+len]
    GC.@preserve vars begin
        ret = _findfirstequal(var, pointer(vars) + 8offset, len)
    end
    return ret < 0 ? nothing : ret + offset + 1
end

# Internal: expanding-binary-search bracket around a guess. Backs the
# `BracketGallop` strategy. Not part of the public API in 2.x — use
# `searchsortedfirst(BracketGallop(), v, x, guess)` /
# `searchsortedlast(BracketGallop(), v, x, guess)` instead.
function bracketstrictlymonotonic(
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

# Internal: companion to `bracketstrictlymonotonic` for the `searchsortedfirst`
# polarity. The original galloping uses `lt(o, x, v[lo])` (i.e., `x < v[lo]`)
# to choose direction, which is the right test for `searchsortedlast`: when
# `x == v[lo]`, the answer is `>= lo` so we gallop right. For
# `searchsortedfirst`, when `x == v[lo]` the answer is `<= lo` (look for
# earlier duplicates) — so we need the inverted polarity `lt(o, v[lo], x)`
# (i.e., `v[lo] < x`). Without this, BracketGallop.searchsortedfirst returns
# the wrong index when the hint lands on a run of duplicates.
function bracketstrictlymonotonic_first(
        v::AbstractVector,
        x,
        guess::T,
        o::Base.Order.Ordering
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
  - [`SIMDLinearScan`](@ref) is `LinearScan` with the forward walk lowered to
    8-wide SIMD chunks for `DenseVector{Int64}` and `DenseVector{Float64}`.
    Falls back to plain [`LinearScan`](@ref) for any other element type.
  - [`BracketGallop`](@ref) expands an exponential bracket bidirectionally
    from the hint, then binary-searches inside it. Effectively O(1) when the
    target is near the hint; never worse than ~2 log₂ n comparisons.
  - [`ExpFromLeft`](@ref) expands rightward from a left-bound hint by
    doubling, then binary-searches inside the final bracket. Best for batched
    sorted queries where each next query's hint is the previous result.
  - [`InterpolationSearch`](@ref) guesses the answer by linearly extrapolating
    between `v[lo]` and `v[hi]`, then refines with a bounded binary search.
    O(1) per query on uniformly-spaced data; falls back to O(log n) on
    irregular data.
  - [`BinaryBracket`](@ref) is the standard `Base.searchsortedlast` /
    `Base.searchsortedfirst` with no hint. Use it when no useful hint exists.
  - [`BisectThenSIMD`](@ref) is an equality-search strategy: binary-bisects
    `v` to a small basecase, then SIMD-scans for exact equality. Specialised
    for `DenseVector{Int64}`; only meaningful when used with
    [`findequal`](@ref).
  - [`Auto`](@ref) heuristically picks one of the above based on the size of
    `v`, the spacing of `v`, and whether a hint was supplied. Accepts an
    optional [`SearchProperties`](@ref) cache to skip per-call probes.

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
    SIMDLinearScan <: SearchStrategy

Variant of [`LinearScan`](@ref) whose forward walk is lowered to 8-wide
SIMD chunks via custom LLVM IR. Specialized for `DenseVector{Int64}` and
`DenseVector{Float64}`; for any other element type, falls back to plain
[`LinearScan`](@ref). The backward walk (when the hint is past the
answer) uses the scalar `LinearScan` path regardless of element type.

Wins on long forward walks (≥ 8 elements past the hint). For walks of
1–3 elements `LinearScan` is comparable — the SIMD chunk has constant
setup overhead. Worst case is O(n / 8) which is still linear, so
`SIMDLinearScan` is only `Auto`-relevant for small `n` or small-gap
batches where plain `LinearScan` would have been picked anyway.

Caveats:
  - Element type must be exactly `Int64` or `Float64`. `Int32`,
    `UInt64`, `Float32`, and user-defined numeric types all fall back to
    scalar.
  - Sorted-Float64 vectors containing `NaN` produce undefined results,
    same as for any positional search on a vector that isn't totally
    ordered.
  - Falls back to [`BinaryBracket`](@ref) when no hint is supplied.
  - Falls back to [`LinearScan`](@ref) for non-`Forward` orderings.
"""
struct SIMDLinearScan <: SearchStrategy end

"""
    BracketGallop <: SearchStrategy

Expand an exponential bracket bidirectionally from the hint, then
binary-search inside the bracket. Effectively O(1) when the target is near
the hint; never worse than ~2 log₂ n comparisons.

Falls back to [`BinaryBracket`](@ref) when no hint is supplied.
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
then binary-search inside the bracket.

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
    BisectThenSIMD <: SearchStrategy

Equality-search strategy. Binary-bisects `v` down to a small basecase, then
SIMD-scans the basecase for exact equality with `x`. Specialised for
`DenseVector{Int64}` + `Int64` queries via the same custom LLVM IR that
backs [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal);
for other element types, falls back to [`BinaryBracket`](@ref) plus an
equality check.

This strategy is meant for use with [`findequal`](@ref FindFirstFunctions.findequal),
not with `searchsortedfirst` / `searchsortedlast` — its purpose is to answer
"is `x` present at exactly which index, or not at all?", which is a
different question from positional search. In the
`searchsortedfirst`/`searchsortedlast` dispatch it falls back to
[`BinaryBracket`](@ref).

Ignores any hint that is supplied. Falls back to [`BinaryBracket`](@ref) for
non-`Forward` orderings.
"""
struct BisectThenSIMD <: SearchStrategy end

"""
    GuesserHint(guesser::Guesser) <: SearchStrategy

Uses a [`Guesser`](@ref) to produce an integer guess for `x`, then dispatches
to [`BracketGallop`](@ref) from that guess. The `Guesser` already decides
between linear-extrapolation lookup (when `v` looks linear) and using the
previous result as a guess; this strategy plugs that logic into the strategy
dispatch hierarchy, and updates `guesser.idx_prev` on each call.

Use this strategy with the per-query and batched APIs whenever you have a
`Guesser` attached to a vector. The cost is one `guesser(x)` evaluation
plus one `BracketGallop` call plus one `idx_prev[]` write per call.
"""
struct GuesserHint{G} <: SearchStrategy
    guesser::G
end

"""
    SearchProperties

Cached, non-allocating facts about a sorted vector. Pass to [`Auto`](@ref)
via `Auto(props)` to skip the per-call probes that the default `Auto()` runs
on every batched call. Stored fields are kept to plain `Bool`s so the struct
stays `isbits` and travels in registers.

Default-constructed (`SearchProperties()`) is the "no information" sentinel:
`has_props` is `false`, the other fields are unspecified and ignored by
`Auto`. Construct via `SearchProperties(v::AbstractVector)` to populate the
fields by running the probes once.

Currently consumed: `is_linear` (replaces Auto's per-call
`_sampled_looks_linear` probe in the batched path). The other fields are
populated for forward compatibility but no built-in strategy reads them yet.
"""
struct SearchProperties
    has_props::Bool
    is_linear::Bool
    has_nan::Bool
end

SearchProperties() = SearchProperties(false, false, false)

# `has_nan` is only meaningful for floating-point eltypes; for other numeric
# types and non-numeric eltypes there is no NaN concept.
@inline _has_nan(v::AbstractVector{<:AbstractFloat}) = any(isnan, v)
@inline _has_nan(::AbstractVector) = false

"""
    SearchProperties(v::AbstractVector; linear_tolerance = 1.0e-3)

Run the linearity probe and (for floating-point eltypes) the NaN scan on `v`,
returning the populated [`SearchProperties`](@ref). Cost is O(n) on
floating-point vectors because of the NaN scan; for integer and non-numeric
eltypes the cost is O(1) — only the sampled-linearity probe runs.

`linear_tolerance` controls the maximum relative deviation accepted by the
sampled-linearity probe. The default `1e-3` (0.1%) matches `Auto`'s
un-cached probe behaviour. Loosen it (e.g. to `1e-2`) to accept noisier
"approximately linear" data — this widens the regime where `Auto` will pick
`InterpolationSearch` over `ExpFromLeft`. Tighten it (e.g. to `1e-4`) to be
more conservative.
"""
function SearchProperties(
        v::AbstractVector;
        linear_tolerance::Real = 1.0e-3,
    )
    return SearchProperties(
        true,
        _sampled_looks_linear(v, Float64(linear_tolerance)),
        _has_nan(v),
    )
end

"""
    Auto <: SearchStrategy
    Auto()
    Auto(props::SearchProperties)

Heuristically picks among [`LinearScan`](@ref), [`ExpFromLeft`](@ref),
[`InterpolationSearch`](@ref), [`BracketGallop`](@ref), and
[`BinaryBracket`](@ref). The choice depends on the calling context:

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
  - `gap ≥ 8`, `length(v) ≥ 1024`, `length(queries) ≥ 2`, and a sampled
    linearity probe (~25 ns) accepts → [`InterpolationSearch`](@ref).
    On uniformly-spaced data this is ~2× faster than `ExpFromLeft` for
    sparse queries; the linearity probe is what keeps `Auto` from picking
    `InterpolationSearch` on irregular data where it would lose badly.
  - otherwise → [`ExpFromLeft`](@ref) (linear probes for very small
    jumps, doubling for medium, bounded binary search for far — always
    moving forward from the previous result, which is what
    `BracketGallop`'s bidirectional bracketing wastes effort on).

**Batched unsorted**: falls back to per-element `Base.searchsortedlast` /
`Base.searchsortedfirst` with no hint regardless of strategy.

**Cached properties.** Passing a populated [`SearchProperties`](@ref) via
`Auto(props)` short-circuits the per-call probes. The cached path is
behaviour-equivalent to `Auto()` when `props` is up to date for `v`; the
caller is responsible for re-computing `props` if `v` mutates.
"""
struct Auto <: SearchStrategy
    props::SearchProperties
end

Auto() = Auto(SearchProperties())

# Per-query Auto threshold: under this length, the bracket-search bookkeeping
# costs more than a worst-case linear walk.
const _AUTO_LINEAR_THRESHOLD = 16

# Batched-Auto crossover: at gap ≤ 4 LinearScan beats ExpFromLeft (its 5
# initial linear probes are wasted when the gap is already 0 or 1).
# Above 4, ExpFromLeft handles arbitrary gap sizes via doubling — the
# bench sweep shows it strictly beats BracketGallop for forward-moving
# sorted queries at gap < ~16.
const _AUTO_BATCH_LINEAR_GAP = 4

# For sparse queries (gap large) on long vectors, InterpolationSearch can
# beat ExpFromLeft by ~2× on uniformly-spaced data. The sampled-linearity
# check below is O(1) — 9 probes — so it's cheap enough to run inside Auto
# when there's a real chance of unlocking InterpolationSearch.
const _AUTO_INTERP_MIN_GAP = 8
const _AUTO_INTERP_MIN_N = 1024
const _AUTO_INTERP_MIN_M = 2
const _AUTO_LINEAR_REL_TOLERANCE = 1.0e-3

# Very-sparse override: when the gap is large enough that ExpFromLeft's
# log₂(gap) doubling levels approach InterpolationSearch's log₂(n) worst-case
# binary refinement, InterpolationSearch's better cache behaviour (one
# extrapolation jump + local refine vs. many doubling probes across the
# array) wins even on non-strictly-linear data — random-sorted vectors
# included, because their order statistics deviate from a straight line by
# O(√n)/n, which is much less than the gap-related cost difference.
#
# At gap ≥ 256, a looser linearity tolerance is used. This still rejects
# genuinely-nonlinear `v` (log-spaced, two-scale), where the bench shows
# InterpolationSearch losing 2–3× to ExpFromLeft, but accepts approximately
# linear data (random_sorted, jittered) where the order-statistic variance
# is well below the loose threshold.
const _AUTO_INTERP_LOOSE_GAP = 256
const _AUTO_LINEAR_LOOSE_TOLERANCE = 5.0e-2

# SIMDLinearScan wins in the medium-gap regime on `DenseVector{Int64}` and
# `DenseVector{Float64}` — 24% of cells in the bench sweep, with median
# 1.94× speedup over plain LinearScan. The threshold is eltype-specific:
#   - Float64: gap ∈ (4, 64]. fcmp is heavier than icmp, so SIMD's 8-wide
#     vector compare wins over the scalar walk at a higher gap than for
#     integers. Bench shows SIMD winning consistently through gap ≈ 64.
#   - Int64: gap ∈ (4, 16]. The scalar icmp loop is so tight that SIMD's
#     constant per-call setup dominates above gap ≈ 16. Bench shows
#     LinearScan recapturing the win above that crossover.
@inline _auto_simd_gap_max(::DenseVector{Int64}) = 64
@inline _auto_simd_gap_max(::DenseVector{Float64}) = 64
@inline _auto_simd_gap_max(::AbstractVector) = 0   # not SIMD-eligible

# When InterpolationSearch isn't eligible and the gap is large, BracketGallop
# beats ExpFromLeft because the 5 linear probes ExpFromLeft does upfront
# are wasted (no chance the answer is within 5 of `hint = prev_result` when
# the gap is hundreds or thousands). BracketGallop just starts doubling
# immediately. The bench sweep shows this crossover at gap ≈ 16.
const _AUTO_GALLOP_GAP_MIN = 16

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
@inline function _sampled_looks_linear(
        v::AbstractVector{<:Number},
        tol::Float64 = _AUTO_LINEAR_REL_TOLERANCE,
    )
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
            rel_err > tol && return false
        end
    end
    return true
end

# Non-numeric eltype: can't sample, never picks InterpolationSearch.
@inline _sampled_looks_linear(::AbstractVector, ::Float64 = _AUTO_LINEAR_REL_TOLERANCE) = false

# AbstractRange is definitionally uniform — accept without sampling.
@inline _sampled_looks_linear(::AbstractRange, ::Float64 = _AUTO_LINEAR_REL_TOLERANCE) = true

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

# Strategy: SIMDLinearScan — specialized forward walk for DenseVector{Int64}
# and DenseVector{Float64}. Backward walks reuse the scalar LinearScan path
# (rare from a good hint, and the SIMD primitive only exists for the
# forward-scan direction).

@inline function _simdscan_last_specialized(
        v::Union{DenseVector{Int64}, DenseVector{Float64}}, x, hint::Integer
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
        v::Union{DenseVector{Int64}, DenseVector{Float64}}, x, hint::Integer
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
        order::Base.Order.Ordering = Base.Order.Forward
    )
    order === Base.Order.Forward ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint)
end
function Base.searchsortedlast(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    order === Base.Order.Forward ||
        return searchsortedlast(LinearScan(), v, x, hint; order = order)
    return _simdscan_last_specialized(v, x, hint)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Int64}, x::Int64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint)
end
function Base.searchsortedfirst(
        ::SIMDLinearScan, v::DenseVector{Float64}, x::Float64, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    order === Base.Order.Forward ||
        return searchsortedfirst(LinearScan(), v, x, hint; order = order)
    return _simdscan_first_specialized(v, x, hint)
end

# Other eltypes fall back to the scalar LinearScan walk.
Base.searchsortedlast(
    ::SIMDLinearScan, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(LinearScan(), v, x, hint; order = order)
Base.searchsortedfirst(
    ::SIMDLinearScan, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(LinearScan(), v, x, hint; order = order)

# No hint → BinaryBracket.
Base.searchsortedlast(
    ::SIMDLinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::SIMDLinearScan, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

# Strategy: BracketGallop — bracketstrictlymonotonic + bounded binary search.
function Base.searchsortedlast(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    lo, hi = bracketstrictlymonotonic(v, x, hint, order)
    return searchsortedlast(v, x, lo, hi, order)
end

function Base.searchsortedfirst(
        ::BracketGallop, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    lo, hi = bracketstrictlymonotonic_first(v, x, hint, order)
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

# Strategy: BisectThenSIMD — only meaningful for `findequal`. For the
# positional `searchsortedfirst` / `searchsortedlast` dispatch, fall back to
# BinaryBracket — bisect-then-equality-scan can't answer the positional
# question ("where would x insert?") that searchsortedfirst asks.
Base.searchsortedlast(
    ::BisectThenSIMD, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::BisectThenSIMD, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedfirst(BinaryBracket(), v, x; order = order)
Base.searchsortedlast(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
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
# queries' distribution is non-uniform within their span. The two pieces of
# information serve different roles in Auto's decision tree:
#
#   - `gap` is the per-query cost driver. We always use the span-based
#     estimate `n * span(queries) / span(v) / m` so that tightly-clustered
#     queries (span_q ≈ 0) report gap ≈ 0 regardless of `n/m`. The earlier
#     `n / m` fallback for skewed queries was wrong: it caused `SIMDLinearScan`
#     to be picked for clustered queries where LinearScan's tiny scalar
#     walk is 5× faster (e.g. clustered queries with span_q = 1 over an
#     `n = 65536` vector).
#   - `skewed` is an InterpolationSearch-suitability flag. When the median
#     query sits well off the midpoint of `queries[1]..queries[end]`, the
#     queries are clustered within their span and the per-call linear
#     extrapolation guess is worse than the previous-result hint that
#     `ExpFromLeft` would use.
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
    ratio = span_q / span_v
    # Clamp ratio: queries may extend outside v's range (extrapolation).
    ratio = clamp(ratio, zero(ratio), one(ratio))
    return (floor(Int, n * ratio / max(1, m)), skewed)
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
`strategy = BracketGallop()` (the default `Auto` choice for non-tiny `v`).

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
        s::Auto, order::Base.Order.Ordering
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
    # Medium-gap regime: SIMDLinearScan wins on `DenseVector{Int64}` and
    # `DenseVector{Float64}` (without NaN). For Float64, NaN presence is
    # taken from `s.props.has_nan` if `SearchProperties(v)` was constructed,
    # else we assume no NaN (consistent with the existing contract that
    # `Base.searchsortedlast` doesn't check sortedness either).
    if gap <= _auto_simd_gap_max(v) &&
            _auto_simd_eligible(v, s.props)
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, SIMDLinearScan(), order
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
            _auto_interp_eligible(v, s.props, gap)
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, InterpolationSearch(), order
        )
    end
    # Sparse fallback: BracketGallop beats ExpFromLeft when the gap is large
    # enough that ExpFromLeft's initial 5 linear probes are guaranteed to
    # miss. BracketGallop starts doubling from one position past `hint`, so
    # it skips the wasted linear preamble.
    if gap >= _AUTO_GALLOP_GAP_MIN
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, BracketGallop(), order
        )
    end
    return _searchsortedlast_sorted_loop!(
        idx_out, v, queries, ExpFromLeft(), order
    )
end

# InterpolationSearch eligibility: two-tier linearity check. For
# `_AUTO_INTERP_MIN_GAP ≤ gap < _AUTO_INTERP_LOOSE_GAP` we require strict
# linearity (`_AUTO_LINEAR_REL_TOLERANCE`, default 0.1%) — InterpolationSearch
# is only worth the per-call cost on truly uniform data when ExpFromLeft is
# also competitive. For `gap ≥ _AUTO_INTERP_LOOSE_GAP` we accept a looser
# tolerance (`_AUTO_LINEAR_LOOSE_TOLERANCE`, default 5%) because the cache
# benefit of one extrapolation jump + local refine compensates for a worse
# guess, but we still reject genuinely nonlinear data (log-spaced,
# two-scale) where InterpolationSearch loses 2–3× to ExpFromLeft.
@inline function _auto_interp_eligible(v, props::SearchProperties, gap::Integer)
    if gap >= _AUTO_INTERP_LOOSE_GAP
        # Loose probe — even on cached props, the strict `is_linear` bit may
        # already reflect a tighter threshold than we need here, so run the
        # sampled probe at the loose tolerance regardless of cache state.
        return _sampled_looks_linear(v, _AUTO_LINEAR_LOOSE_TOLERANCE)
    end
    return props.has_props ? props.is_linear : _sampled_looks_linear(v)
end

# SIMD eligibility check used by Auto's batched dispatch. The static type
# test on `v` discriminates the `DenseVector{Int64}` / `DenseVector{Float64}`
# cases that SIMDLinearScan supports. For Float64, NaN presence is taken
# from cached `SearchProperties.has_nan` when available; otherwise we
# assume no NaN — Base's positional search doesn't check sortedness either,
# and the burden of supplying populated props is on the caller for
# pathological inputs.
@inline _auto_simd_eligible(v::DenseVector{Int64}, ::SearchProperties) = true
@inline function _auto_simd_eligible(v::DenseVector{Float64}, p::SearchProperties)
    return p.has_props ? !p.has_nan : true
end
@inline _auto_simd_eligible(::AbstractVector, ::SearchProperties) = false

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
        s::Auto, order::Base.Order.Ordering
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
    if gap <= _auto_simd_gap_max(v) &&
            _auto_simd_eligible(v, s.props)
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, SIMDLinearScan(), order
        )
    end
    if !skewed &&
            gap >= _AUTO_INTERP_MIN_GAP &&
            length(v) >= _AUTO_INTERP_MIN_N &&
            m >= _AUTO_INTERP_MIN_M &&
            _auto_interp_eligible(v, s.props, gap)
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, InterpolationSearch(), order
        )
    end
    if gap >= _AUTO_GALLOP_GAP_MIN
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, BracketGallop(), order
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

# Internal: exponential search forward from `lo`, then bounded binary search.
# Backs the `ExpFromLeft` strategy. Not part of the public API in 2.x — use
# `searchsortedfirst(ExpFromLeft(), v, x, lo)` instead.
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

# ---------------------------------------------------------------------------
# Equality search through the strategy dispatch
# ---------------------------------------------------------------------------

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
        order::Base.Order.Ordering = Base.Order.Forward
    )
    return _findequal_generic(strategy, v, x, order)
end

@inline function findequal(
        strategy::SearchStrategy, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward
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
        order::Base.Order.Ordering = Base.Order.Forward
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
    order::Base.Order.Ordering = Base.Order.Forward
) = findequal(s, v, x; order = order)

# Non-Int64 fallback for BisectThenSIMD: use BinaryBracket + post-check.
function findequal(
        ::BisectThenSIMD, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward
    )
    return _findequal_generic(BinaryBracket(), v, x, order)
end
findequal(
    s::BisectThenSIMD, v::AbstractVector, x, ::Integer;
    order::Base.Order.Ordering = Base.Order.Forward
) = findequal(s, v, x; order = order)

using PrecompileTools: @compile_workload, @setup_workload

@setup_workload begin
    # Minimal setup for precompilation workload
    vec_int64 = Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    linear_vec = collect(1.0:0.5:10.0)

    @compile_workload begin
        # Precompile the most commonly used functions with typical types.

        # findfirstequal: fast SIMD-based search in Int64 vectors.
        findfirstequal(Int64(5), vec_int64)
        findfirstequal(Int64(100), vec_int64)

        # findfirstsortedequal: binary search in sorted Int64 vectors.
        findfirstsortedequal(Int64(8), vec_int64)
        findfirstsortedequal(Int64(100), vec_int64)

        # looks_linear: check if vector is evenly spaced.
        looks_linear(linear_vec)

        # Guesser: hint provider for correlated repeated searches.
        guesser = Guesser(linear_vec)
        guesser(5.0)

        # Strategy dispatch — single-query forms across the standard strategies.
        for strategy in (
                LinearScan(), SIMDLinearScan(), BracketGallop(), ExpFromLeft(),
                InterpolationSearch(), BinaryBracket(), Auto(),
                Auto(SearchProperties(linear_vec)),
            )
            searchsortedfirst(strategy, vec_int64, Int64(8), Int64(1))
            searchsortedlast(strategy, vec_int64, Int64(8), Int64(1))
        end
        # findequal: generic + BisectThenSIMD shortcut for Int64 dense vectors.
        for strategy in (
                BinaryBracket(), BracketGallop(), SIMDLinearScan(),
                BisectThenSIMD(), Auto(),
            )
            findequal(strategy, vec_int64, Int64(8))
            findequal(strategy, vec_int64, Int64(8), Int64(1))
        end
        # SIMDLinearScan's Float64 specialization.
        let vec_f64 = collect(1.0:1.0:16.0)
            searchsortedfirst(SIMDLinearScan(), vec_f64, 8.0, 1)
            searchsortedlast(SIMDLinearScan(), vec_f64, 8.0, 1)
        end
        searchsortedfirst(GuesserHint(Guesser(vec_int64)), vec_int64, Int64(8))
        searchsortedlast(GuesserHint(Guesser(vec_int64)), vec_int64, Int64(8))

        # Strategy dispatch — batched in-place forms.
        idx_out = Vector{Int}(undef, 4)
        queries = Int64[2, 5, 8, 12]
        searchsortedfirst!(idx_out, vec_int64, queries)
        searchsortedlast!(idx_out, vec_int64, queries)
    end
end

end # module FindFirstFunctions

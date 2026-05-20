# Auto strategy — heuristic dispatch tree + crossover constants + the
# helpers (`_estimate_avg_gap`, `_auto_simd_*`, `_auto_interp_eligible`) it
# consults. Per-query Auto dispatch lives here; batched Auto dispatch lives
# in `batched.jl` (next to the generic `_batched!` it specializes).

# Per-query Auto threshold: under this length, the bracket-search bookkeeping
# costs more than a worst-case linear walk.
const _AUTO_LINEAR_THRESHOLD = 16

# Batched-Auto crossover: at gap ≤ 4 LinearScan beats ExpFromLeft (its 5
# initial linear probes are wasted when the gap is already 0 or 1). Above 4,
# the SIMD path picks up (where eligible) up to gap = `_auto_simd_gap_max`.
const _AUTO_BATCH_LINEAR_GAP = 4

# For sparse queries (gap large) on long vectors, InterpolationSearch can
# beat ExpFromLeft by ~2× on uniformly-spaced data. The sampled-linearity
# check is O(1) — 9 probes — so it's cheap enough to run inside Auto when
# there's a real chance of unlocking InterpolationSearch.
const _AUTO_INTERP_MIN_GAP = 8
const _AUTO_INTERP_MIN_N = 1024
const _AUTO_INTERP_MIN_M = 2

# Very-sparse override: when the gap is large enough that ExpFromLeft's
# log₂(gap) doubling levels approach InterpolationSearch's log₂(n) worst-case
# binary refinement, InterpolationSearch's better cache behaviour (one
# extrapolation jump + local refine vs. many doubling probes across the
# array) wins even on non-strictly-linear data.
const _AUTO_INTERP_LOOSE_GAP = 256
const _AUTO_LINEAR_LOOSE_TOLERANCE = 5.0e-2

# SIMDLinearScan eligibility window. The threshold is eltype-parameterized
# via the `_auto_simd_gap_max` function below.
@inline _auto_simd_gap_max(::DenseVector{Int64}) = 64
@inline _auto_simd_gap_max(::DenseVector{Float64}) = 64
@inline _auto_simd_gap_max(::AbstractVector) = 0   # not SIMD-eligible

# When InterpolationSearch isn't eligible and the gap is large, BracketGallop
# beats ExpFromLeft because the 5 linear probes ExpFromLeft does upfront are
# wasted (no chance the answer is within 5 of `hint = prev_result` when the
# gap is hundreds or thousands). BracketGallop just starts doubling
# immediately. The bench sweep shows this crossover at gap ≈ 16.
const _AUTO_GALLOP_GAP_MIN = 16

# Per-query Auto: pick based on hint validity and length(v).
@inline function _auto_pick(v::AbstractVector, hint::Integer)
    return if hint < firstindex(v) || hint > lastindex(v)
        BinaryBracket()
    elseif length(v) <= _AUTO_LINEAR_THRESHOLD
        LinearScan()
    else
        BracketGallop()
    end
end

# Returns `(gap, skewed)`: the estimated average step in `v`'s index space
# between consecutive query results, plus a flag that's true when the
# queries' distribution is non-uniform within their span.
#
#   - `gap` is the per-query cost driver. We always use the span-based
#     estimate `n * span(queries) / span(v) / m` so that tightly-clustered
#     queries (span_q ≈ 0) report gap ≈ 0 regardless of `n/m`. The earlier
#     `n / m` fallback for skewed queries caused `SIMDLinearScan` to be
#     picked for clustered queries where LinearScan's tiny scalar walk is
#     5× faster.
#   - `skewed` is an InterpolationSearch-suitability flag. When the median
#     query sits well off the midpoint of `queries[1]..queries[end]`, the
#     queries are clustered within their span and the per-call linear
#     extrapolation guess is worse than the previous-result hint that
#     `ExpFromLeft` would use.
@inline function _estimate_avg_gap(
        v::AbstractVector{<:Number}, queries::AbstractVector{<:Number}, m::Integer,
    )
    n = length(v)
    n <= 1 && return (0, false)
    @inbounds span_v = v[end] - v[1]
    if iszero(span_v) || !isfinite(span_v)
        return (n ÷ max(1, m), false)
    end
    @inbounds span_q = queries[end] - queries[1]
    # Skew detection on small `m` is too noisy — for `m ≈ 4` random uniform
    # samples, the median routinely sits 30%+ off the linear midpoint by
    # chance. Gate on `m ≥ 10` where the statistical variance is well below
    # the 20% threshold.
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

# Non-numeric eltypes: no span subtraction possible, fall back to length
# ratio and assume queries are roughly uniform (no skew detection possible).
@inline _estimate_avg_gap(
    v::AbstractVector, ::AbstractVector, m::Integer,
) = (length(v) ÷ max(1, m), false)

# SIMD eligibility check used by Auto's batched dispatch. The static type
# test on `v` discriminates the `DenseVector{Int64}` / `DenseVector{Float64}`
# cases that SIMDLinearScan supports. For Float64, NaN presence is taken from
# cached `SearchProperties.has_nan` when available; otherwise we assume no
# NaN — Base's positional search doesn't check sortedness either, and the
# burden of supplying populated props is on the caller for pathological
# inputs.
@inline _auto_simd_eligible(v::DenseVector{Int64}, ::SearchProperties) = true
@inline function _auto_simd_eligible(v::DenseVector{Float64}, p::SearchProperties)
    return p.has_props ? !p.has_nan : true
end
@inline _auto_simd_eligible(::AbstractVector, ::SearchProperties) = false

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

# Per-query Auto dispatch.
function Base.searchsortedlast(
        ::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    s = _auto_pick(v, hint)
    return s isa BinaryBracket ?
        searchsortedlast(s, v, x; order = order) :
        searchsortedlast(s, v, x, hint; order = order)
end

function Base.searchsortedfirst(
        ::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    s = _auto_pick(v, hint)
    return s isa BinaryBracket ?
        searchsortedfirst(s, v, x; order = order) :
        searchsortedfirst(s, v, x, hint; order = order)
end

Base.searchsortedlast(
    ::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedlast(BinaryBracket(), v, x; order = order)
Base.searchsortedfirst(
    ::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsortedfirst(BinaryBracket(), v, x; order = order)

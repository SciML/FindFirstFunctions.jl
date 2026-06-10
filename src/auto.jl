# Auto strategy — resolves a `StrategyKind` from `(v, props)` at
# construction time. Per-query dispatch is then a one-line forward to
# `search_last` / `search_first` on the stored kind. The batched dispatch
# (in `batched.jl`) re-resolves the kind from `(v, queries)` because the
# gap heuristic needs the queries.
#
# This file owns:
#   - The crossover constants (`_AUTO_LINEAR_THRESHOLD`, etc.)
#   - The helper predicates (`_auto_is_uniform`, `_auto_simd_eligible`,
#     `_estimate_avg_gap`, `_auto_interp_eligible`, …)
#   - `_auto_resolve_kind(v, props)` — forward-declared in `strategies.jl`
#   - The per-query `search_last(::Auto, ...)` / `search_first(::Auto, ...)`
#     methods + their `Base.searchsortedlast(::Auto, ...)` back-compat shims.

# Per-query Auto threshold: under this length, the bracket-search bookkeeping
# costs more than a worst-case linear walk.
const _AUTO_LINEAR_THRESHOLD = 16

# Batched-Auto crossover: at gap ≤ 4 LinearScan beats ExpFromLeft.
const _AUTO_BATCH_LINEAR_GAP = 4

# Sparse-on-large-linear: InterpolationSearch beats ExpFromLeft.
const _AUTO_INTERP_MIN_GAP = 8
const _AUTO_INTERP_MIN_N = 1024
const _AUTO_INTERP_MIN_M = 2

# Very-sparse override: looser linearity tolerance at large gaps.
const _AUTO_INTERP_LOOSE_GAP = 256
const _AUTO_LINEAR_LOOSE_TOLERANCE = 5.0e-2

# SIMDLinearScan eligibility window. The threshold is eltype-parameterized.
@inline _auto_simd_gap_max(::DenseVector{Int64}) = 64
@inline _auto_simd_gap_max(::DenseVector{Float64}) = 64
@inline _auto_simd_gap_max(::AbstractVector) = 0   # not SIMD-eligible

# When InterpolationSearch isn't eligible and the gap is large,
# BracketGallop beats ExpFromLeft.
const _AUTO_GALLOP_GAP_MIN = 16

# Returns `(gap, skewed)`: the estimated average step in `v`'s index space
# between consecutive query results, plus a flag that's true when the
# queries' distribution is non-uniform within their span.
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
    ratio = clamp(ratio, zero(ratio), one(ratio))
    return (floor(Int, n * ratio / max(1, m)), skewed)
end

# Non-numeric eltypes.
@inline _estimate_avg_gap(
    v::AbstractVector, ::AbstractVector, m::Integer,
) = (length(v) ÷ max(1, m), false)

# SIMD eligibility for the batched Auto dispatch.
@inline _auto_simd_eligible(v::DenseVector{Int64}, ::SearchProperties) = true
@inline function _auto_simd_eligible(v::DenseVector{Float64}, p::SearchProperties)
    return p.has_props ? !p.has_nan : true
end
@inline _auto_simd_eligible(::AbstractVector, ::SearchProperties) = false

# Uniformity check. `AbstractRange{<:Real}` is always uniform; for non-Real
# range eltypes (e.g. Unitful `StepRange{Quantity}`) the props-aware
# closed-form path is unsafe, so we fall through to the `is_uniform` flag
# in `props` — which is `false` for non-Real numeric eltypes (set by the
# `SearchProperties(::AbstractVector{<:Number})` overload).
@inline _auto_is_uniform(::AbstractRange{<:Real}, ::SearchProperties) = true
@inline _auto_is_uniform(::AbstractVector, p::SearchProperties) =
    p.has_props && p.is_uniform

# InterpolationSearch eligibility: two-tier linearity check.
@inline function _auto_interp_eligible(v, props::SearchProperties, gap::Integer)
    if gap >= _AUTO_INTERP_LOOSE_GAP
        return _sampled_looks_linear(v, _AUTO_LINEAR_LOOSE_TOLERANCE)
    end
    return props.has_props ? props.is_linear : _sampled_looks_linear(v)
end

# `_auto_resolve_kind` is forward-declared in `strategies.jl` so `Auto(v)`
# can call it from the struct's constructor. The body lives here so it can
# use the helpers above. This is *construction-time* resolution — the hint
# isn't known yet, so we pick a kind that handles every hint configuration
# robustly.
@inline function _auto_resolve_kind(v::AbstractVector, props::SearchProperties)
    if _auto_is_uniform(v, props)
        return KIND_UNIFORM_STEP
    elseif length(v) <= _AUTO_LINEAR_THRESHOLD
        return KIND_LINEAR_SCAN
    else
        return KIND_BRACKET_GALLOP
    end
end

# ---------------------------------------------------------------------------
# Per-query Auto dispatch. The stored kind handles every hint configuration
# robustly — `BracketGallop` falls back to a full search when the hint is
# absent or out of range; `LinearScan` (picked for short `v`) clamps the
# hint and walks. So `search_last(::Auto, v, x, hint)` is a one-line
# forward to the kind dispatcher.
#
# Special case: when `kind === KIND_UNIFORM_STEP` and `props` is
# populated, we route to the props-aware kernel that uses the precomputed
# `inv_step` from `props`, skipping the per-query float division in the
# back-compat AbstractRange `UniformStep` kernel. An `Auto` holding the
# sentinel `SearchProperties()` has `inv_step = 0`, which would silently
# degrade the closed-form guess to a linear walk — the `has_props` guard
# sends it to the `fld`-based kind kernel instead, matching the guard in
# the batched path.
# ---------------------------------------------------------------------------

# Hinted form: forward to the kind dispatcher.
@inline function search_last(
        s::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return if s.kind === KIND_UNIFORM_STEP && s.props.has_props
        _kernel_last_uniform_step_props(s.props, v, x, order)
    else
        search_last(s.kind, v, x, hint; order = order)
    end
end

@inline function search_first(
        s::Auto, v::AbstractVector, x, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return if s.kind === KIND_UNIFORM_STEP && s.props.has_props
        _kernel_first_uniform_step_props(s.props, v, x, order)
    else
        search_first(s.kind, v, x, hint; order = order)
    end
end

# No-hint form: same forward. The kind's no-hint dispatch handles
# fall-through to BinaryBracket for hint-using strategies.
@inline function search_last(
        s::Auto, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return if s.kind === KIND_UNIFORM_STEP && s.props.has_props
        _kernel_last_uniform_step_props(s.props, v, x, order)
    else
        search_last(s.kind, v, x; order = order)
    end
end

@inline function search_first(
        s::Auto, v::AbstractVector, x;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    return if s.kind === KIND_UNIFORM_STEP && s.props.has_props
        _kernel_first_uniform_step_props(s.props, v, x, order)
    else
        search_first(s.kind, v, x; order = order)
    end
end

# Legacy `Base.searchsortedlast(::Auto, ...)` shims — same one-liner. Kept
# so v2 callers continue to work without changes.
Base.searchsortedlast(
    s::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = search_last(s, v, x; order = order)
Base.searchsortedfirst(
    s::Auto, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = search_first(s, v, x; order = order)
Base.searchsortedlast(
    s::Auto, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = search_last(s, v, x, hint; order = order)
Base.searchsortedfirst(
    s::Auto, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = search_first(s, v, x, hint; order = order)

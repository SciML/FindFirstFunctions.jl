# `SearchProperties` populated constructor + the runtime probes it runs at
# construction time. The `SearchProperties` struct itself, the default
# constructor (`SearchProperties()` sentinel), and the `Auto` type that
# carries one as a field all live in `strategies.jl`.

# `has_nan` is only meaningful for floating-point eltypes; for other numeric
# types and non-numeric eltypes there is no NaN concept.
@inline _has_nan(v::AbstractVector{<:AbstractFloat}) = any(isnan, v)
@inline _has_nan(::AbstractVector) = false

# Auto's strict linearity tolerance. `SearchProperties(v)` uses the same
# default. Defined here rather than in `auto.jl` because `_sampled_looks_*`
# need it as a default arg; `auto.jl` re-uses the same constant.
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

# Sampled "log-linear" probe: same 9-point probe as `_sampled_looks_linear`
# but tests whether `log(v)` is linear in array index. Used to detect
# geometric / log-spaced data where `BitInterpolationSearch` is a win.
# Requires all sampled points to be strictly positive and finite; otherwise
# returns false. The probe runs in ~30 ns (the `log` calls are not cheap
# but only 11 of them, all at fixed index positions).
@inline function _sampled_looks_log_linear(
        v::AbstractVector{<:Real},
        tol::Float64 = _AUTO_LINEAR_REL_TOLERANCE,
    )
    n = length(v)
    n < 11 && return false
    @inbounds begin
        v1, vn = v[1], v[n]
        (v1 <= 0 || vn <= 0 || !isfinite(v1) || !isfinite(vn)) && return false
        log_v1 = log(Float64(v1))
        log_vn = log(Float64(vn))
        span = log_vn - log_v1
        (iszero(span) || !isfinite(span)) && return false
        abs_span = abs(span)
        nm1 = n - 1
        for k in 1:9
            kk = 1 + (k * nm1) ÷ 10
            vk = v[kk]
            (vk <= 0 || !isfinite(vk)) && return false
            expected = log_v1 + (kk - 1) / nm1 * span
            rel_err = abs(log(Float64(vk)) - expected) / abs_span
            rel_err > tol && return false
        end
    end
    return true
end

@inline _sampled_looks_log_linear(::AbstractVector, ::Float64 = _AUTO_LINEAR_REL_TOLERANCE) = false

"""
    SearchProperties(v::AbstractVector; linear_tolerance = 1.0e-3, is_uniform = false)

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

`is_uniform` is a caller-supplied flag for `Vector`s that are exactly
uniformly spaced. Setting it `true` opts the vector into
[`UniformStep`](@ref)'s closed-form O(1) path via `Auto`. There is no
detection probe — uniform spacing on a `Vector` can't be confirmed
cheaply, and an approximate-uniform vector would give wrong answers
under `UniformStep`'s exact-step assumption. For `AbstractRange` inputs
the flag is set automatically by the dedicated overload below.
"""
function SearchProperties(
        v::AbstractVector;
        linear_tolerance::Real = 1.0e-3,
        is_uniform::Bool = false,
    )
    tol = Float64(linear_tolerance)
    return SearchProperties(
        true,
        _sampled_looks_linear(v, tol),
        _has_nan(v),
        _sampled_looks_log_linear(v, tol),
        is_uniform,
    )
end

"""
    SearchProperties(v::AbstractRange; linear_tolerance = 1.0e-3)

Specialised constructor for `AbstractRange`. Sets `is_uniform = true`
unconditionally — every `AbstractRange` is by definition uniformly
spaced, so `Auto` can short-circuit to [`UniformStep`](@ref).
"""
function SearchProperties(
        v::AbstractRange;
        linear_tolerance::Real = 1.0e-3,
    )
    tol = Float64(linear_tolerance)
    return SearchProperties(
        true,
        _sampled_looks_linear(v, tol),
        _has_nan(v),
        _sampled_looks_log_linear(v, tol),
        true,
    )
end

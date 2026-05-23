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
# computes the maximum relative deviation of the 9 interior points from
# the straight line between v[1] and v[n]. Returns the max relative error
# (or `Inf` if `v` is unsuitable — too short, zero/infinite span, etc.).
#
# A single scan produces several different bool flags by comparing the
# returned error against different tolerances:
#
#   - `_AUTO_LINEAR_REL_TOLERANCE` (default 0.1%) gates `InterpolationSearch`
#     in Auto's batched dispatch.
#   - `_AUTO_LINEAR_LOOSE_TOLERANCE` (5%) for the large-gap regime.
#   - `_UNIFORM_REL_TOLERANCE` (~1e-12, a few ulp) flags
#     exactly-uniformly-spaced data so `SearchProperties` can set
#     `is_uniform` for any `AbstractVector` (not just `AbstractRange`).
#
# Cost is ~25 ns regardless of n — 11 reads + 9 multiply/add + 9 compares.
# Tight tolerance reliably distinguishes truly-uniform data from random
# sorted data even at large n (where order-statistic variance ≈ 1/sqrt(n)
# would fool a looser check).
@inline function _sampled_linear_err(
        v::AbstractVector{<:Number},
    )
    n = length(v)
    n < 11 && return Inf
    @inbounds begin
        v1, vn = v[1], v[n]
        span = vn - v1
        (iszero(span) || !isfinite(span)) && return Inf
        abs_span = abs(span)
        nm1 = n - 1
        max_err = 0.0
        for k in 1:9
            kk = 1 + (k * nm1) ÷ 10
            expected = v1 + (kk - 1) / nm1 * span
            rel_err = Float64(abs(v[kk] - expected) / abs_span)
            rel_err > max_err && (max_err = rel_err)
        end
        return max_err
    end
end

# Non-numeric eltype: can't sample. Returns Inf so every tolerance check fails.
@inline _sampled_linear_err(::AbstractVector) = Inf

# AbstractRange is definitionally uniform — error is zero by construction.
@inline _sampled_linear_err(::AbstractRange) = 0.0

# Tolerance treating "uniform" as a few ulp of accumulated float roundoff.
# `collect(0.0:0.1:10.0)` has rel_err ≈ 1e-16 to 1e-15 from float-step
# imprecision; `1e-12` accepts it cleanly. Random / jittered data at any
# n has rel_err well above this. The constant is conservative — tightening
# further would risk false negatives on long Float ranges.
const _UNIFORM_REL_TOLERANCE = 1.0e-12

@inline _sampled_looks_linear(
    v::AbstractVector, tol::Float64 = _AUTO_LINEAR_REL_TOLERANCE,
) = _sampled_linear_err(v) <= tol

@inline _sampled_looks_uniform(v::AbstractVector) =
    _sampled_linear_err(v) <= _UNIFORM_REL_TOLERANCE

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
    SearchProperties(v::AbstractVector; linear_tolerance = 1.0e-3, is_uniform = nothing)

Run the linearity probe and (for floating-point eltypes) the NaN scan on `v`,
returning the populated [`SearchProperties{T}`](@ref) where `T` is the data
ratio type (e.g. `Float64` for `Vector{Int}` or `Vector{Float64}`,
`Float32` for `Vector{Float32}`). Cost is O(n) on floating-point vectors
because of the NaN scan; for integer and non-numeric eltypes the cost is
O(1) — only the sampled-linearity probe runs.

`linear_tolerance` controls the maximum relative deviation accepted by the
sampled-linearity probe. The default `1e-3` (0.1%) matches `Auto`'s
un-cached probe behaviour. Loosen it (e.g. to `1e-2`) to accept noisier
"approximately linear" data — this widens the regime where `Auto` will pick
`InterpolationSearch` over `ExpFromLeft`. Tighten it (e.g. to `1e-4`) to be
more conservative.

`is_uniform` is a caller-supplied flag for `Vector`s that are exactly
uniformly spaced. Setting it `true` opts the vector into
[`UniformStep`](@ref)'s closed-form O(1) path via `Auto`. The default
`nothing` infers from the tight uniformity probe. When `true` (either
detected or supplied), `first_val` and `inv_step` are computed and stored
in the result so `UniformStep`'s closed-form path needs no per-query
division.
"""
function SearchProperties(
        v::AbstractVector{<:Number};
        linear_tolerance::Real = 1.0e-3,
        is_uniform::Union{Nothing, Bool} = nothing,
    )
    T = _ratio_type(eltype(v))
    tol = Float64(linear_tolerance)
    # One scan produces both `is_linear` and the uniformity-deviation
    # check. `is_uniform = nothing` (default) means "infer from the
    # probe"; an explicit Bool overrides.
    err = _sampled_linear_err(v)
    detected_uniform = err <= _UNIFORM_REL_TOLERANCE
    flag_uniform = is_uniform === nothing ? detected_uniform : is_uniform
    first_val, inv_step = if flag_uniform && length(v) >= 2
        # Closed-form `inv_step` from sampled endpoints. Promotes Int → Float64.
        @inbounds T(v[1]), T(length(v) - 1) / T(v[end] - v[1])
    else
        zero(T), zero(T)
    end
    return SearchProperties{T}(
        true,
        err <= tol,
        _has_nan(v),
        _sampled_looks_log_linear(v, tol),
        flag_uniform,
        first_val,
        inv_step,
    )
end

# Non-numeric eltype: `Float64` default T, `has_props = false`. Probes are
# meaningless on non-Number data, so the result is the sentinel value.
function SearchProperties(
        v::AbstractVector;
        linear_tolerance::Real = 1.0e-3,
        is_uniform::Union{Nothing, Bool} = nothing,
    )
    return SearchProperties()
end

"""
    SearchProperties(v::AbstractRange; linear_tolerance = 1.0e-3)

Specialised constructor for `AbstractRange{<:Real}`. Skips every runtime
probe — every property is known statically from the type:

  - `is_linear = true` — ranges are linear in index by construction.
  - `is_uniform = true` — ranges have exact uniform spacing.
  - `has_nan = false` — `AbstractRange{<:Real}` values are computed from
    `first(r) + (i - 1) * step(r)`; barring `first(r)` or `step(r)`
    themselves being NaN, the values are all finite. For the rare
    pathological `LinRange(NaN, …, …)` case the caller is on their own.
  - `is_log_linear = false` — a range that's linear in index is *not*
    log-linear in value (the values are arithmetically, not
    geometrically, spaced). The flag would only be `true` for ranges of
    `exp(x)` values, which Julia represents as a `Vector`, not an
    `AbstractRange`.

The `first_val` and `inv_step` fields are populated from `first(r)` and
`1/step(r)` to skip the per-query division in `UniformStep`'s closed-form
path.

`linear_tolerance` is accepted for signature compatibility but ignored
— the probes are skipped.
"""
function SearchProperties(
        v::AbstractRange{<:Real};
        linear_tolerance::Real = 1.0e-3,
    )
    T = _ratio_type(eltype(v))
    first_val, inv_step = if length(v) >= 1
        f = T(first(v))
        s = T(step(v))
        if iszero(s)
            f, zero(T)
        else
            f, one(T) / s
        end
    else
        zero(T), zero(T)
    end
    return SearchProperties{T}(
        true, true, false, false, true, first_val, inv_step,
    )
end

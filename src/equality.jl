# Equality-search public surface. `findfirstequal` handles unsorted vectors
# (with a SIMD specialization for `DenseVector{Int64}`); `findfirstsortedequal`
# handles sorted vectors via bisect-then-SIMD. The strategy-framework
# wrapper `findequal(strategy, v, x)` lives in `findequal.jl`.

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
        ::Val{basecase} = Base.libllvm_version >= v"17" ? Val(8) : Val(128),
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

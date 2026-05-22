# In-place batched sorted-search API: `searchsortedfirst!` /
# `searchsortedlast!` and `searchsortedrange`, plus the internal
# `_batched!` dispatchers and the Auto-specific specialization that turns
# Auto's decision tree into a single dispatch on a concrete kind.

"""
    searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward,
                       queries_sorted = nothing)

In-place batched [`searchsortedlast`](@ref Base.searchsortedlast). Writes
one index per element of `queries` into `idx_out` (which must be the same
length).

If `queries` is sorted under `order`, the previous result is used as a
hint for the next query, so the total cost is O(length(v) + length(queries))
under `strategy = BracketGallop()`.

If `queries` is not sorted, falls back to per-element `searchsortedlast`
with no hint regardless of `strategy`.

The `queries_sorted` kwarg controls the runtime `issorted(queries)` check:

  - `nothing` (default): run `issorted(queries; order = order)` on every call.
  - `true`: skip the check and take the sorted-loop path unconditionally.
  - `false`: skip the check and take the unsorted-loop path unconditionally.

Returns `idx_out`.
"""
function searchsortedlast!(
        idx_out::AbstractVector{<:Integer},
        v::AbstractVector,
        queries::AbstractVector;
        strategy::SearchStrategy = Auto(),
        order::Base.Order.Ordering = Base.Order.Forward,
        queries_sorted::Union{Nothing, Bool} = nothing,
    )
    if length(idx_out) != length(queries)
        throw(
            DimensionMismatch(
                "idx_out and queries must have the same length"
            )
        )
    end
    return _searchsortedlast_batched!(
        idx_out, v, queries, strategy, order, queries_sorted
    )
end

"""
    searchsortedfirst!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward,
                        queries_sorted = nothing)

In-place batched [`searchsortedfirst`](@ref Base.searchsortedfirst). See
[`searchsortedlast!`](@ref) for behavior.
"""
function searchsortedfirst!(
        idx_out::AbstractVector{<:Integer},
        v::AbstractVector,
        queries::AbstractVector;
        strategy::SearchStrategy = Auto(),
        order::Base.Order.Ordering = Base.Order.Forward,
        queries_sorted::Union{Nothing, Bool} = nothing,
    )
    if length(idx_out) != length(queries)
        throw(
            DimensionMismatch(
                "idx_out and queries must have the same length"
            )
        )
    end
    return _searchsortedfirst_batched!(
        idx_out, v, queries, strategy, order, queries_sorted
    )
end

# Sorted inner loop parameterized on a `StrategyKind` — concrete kernel
# dispatch happens inside `search_last` via the enum switch.
function _searchsortedlast_sorted_loop_kind!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        kind::StrategyKind, order::Base.Order.Ordering,
    )
    hint = firstindex(v) - 1
    @inbounds for k in eachindex(queries)
        q = queries[k]
        hint = if hint < firstindex(v)
            search_last(kind, v, q; order = order)
        else
            search_last(kind, v, q, hint; order = order)
        end
        idx_out[k] = hint
    end
    return idx_out
end

function _searchsortedfirst_sorted_loop_kind!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        kind::StrategyKind, order::Base.Order.Ordering,
    )
    hint = firstindex(v) - 1
    @inbounds for k in eachindex(queries)
        q = queries[k]
        hint = if hint < firstindex(v)
            search_first(kind, v, q; order = order)
        else
            search_first(kind, v, q, hint; order = order)
        end
        idx_out[k] = hint
    end
    return idx_out
end

# Sorted inner loop parameterized on a strategy *struct* (for GuesserHint
# and for the back-compat `Base.searchsortedlast(::S, ...)` path).
function _searchsortedlast_sorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering,
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
        strategy::SearchStrategy, order::Base.Order.Ordering,
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
        order::Base.Order.Ordering,
    )
    @inbounds for k in eachindex(queries)
        idx_out[k] = searchsortedlast(v, queries[k], order)
    end
    return idx_out
end

function _searchsortedfirst_unsorted_loop!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        order::Base.Order.Ordering,
    )
    @inbounds for k in eachindex(queries)
        idx_out[k] = searchsortedfirst(v, queries[k], order)
    end
    return idx_out
end

@inline function _take_sorted_path(
        queries, order::Base.Order.Ordering, queries_sorted::Union{Nothing, Bool},
    )
    return queries_sorted === nothing ?
        issorted(queries; order = order) : queries_sorted
end

# Generic strategy path: singleton struct routes through its kind; other
# struct strategies (GuesserHint) route through their multimethod.
function _searchsortedlast_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    return if _take_sorted_path(queries, order, queries_sorted)
        _searchsortedlast_sorted_loop_strategy_dispatch!(
            idx_out, v, queries, strategy, order
        )
    else
        _searchsortedlast_unsorted_loop!(idx_out, v, queries, order)
    end
end

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    return if _take_sorted_path(queries, order, queries_sorted)
        _searchsortedfirst_sorted_loop_strategy_dispatch!(
            idx_out, v, queries, strategy, order
        )
    else
        _searchsortedfirst_unsorted_loop!(idx_out, v, queries, order)
    end
end

# Dispatch helper: route singleton struct → kind loop, stateful struct →
# struct loop. Inlining means no extra cost vs. the v2 single-loop form.
@inline function _searchsortedlast_sorted_loop_strategy_dispatch!(
        idx_out, v, queries, strategy::SearchStrategy, order,
    )
    return _searchsortedlast_sorted_loop!(idx_out, v, queries, strategy, order)
end
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BinaryBracket, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_BINARY_BRACKET, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::LinearScan, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_LINEAR_SCAN, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::SIMDLinearScan, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_SIMD_LINEAR_SCAN, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BracketGallop, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_BRACKET_GALLOP, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::ExpFromLeft, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_EXP_FROM_LEFT, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::InterpolationSearch, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_INTERPOLATION_SEARCH, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BitInterpolationSearch, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_BIT_INTERPOLATION_SEARCH, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::UniformStep, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_UNIFORM_STEP, order)
@inline _searchsortedlast_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BisectThenSIMD, order,
) = _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, KIND_BISECT_THEN_SIMD, order)

@inline function _searchsortedfirst_sorted_loop_strategy_dispatch!(
        idx_out, v, queries, strategy::SearchStrategy, order,
    )
    return _searchsortedfirst_sorted_loop!(idx_out, v, queries, strategy, order)
end
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BinaryBracket, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_BINARY_BRACKET, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::LinearScan, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_LINEAR_SCAN, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::SIMDLinearScan, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_SIMD_LINEAR_SCAN, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BracketGallop, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_BRACKET_GALLOP, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::ExpFromLeft, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_EXP_FROM_LEFT, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::InterpolationSearch, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_INTERPOLATION_SEARCH, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BitInterpolationSearch, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_BIT_INTERPOLATION_SEARCH, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::UniformStep, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_UNIFORM_STEP, order)
@inline _searchsortedfirst_sorted_loop_strategy_dispatch!(
    idx_out, v, queries, ::BisectThenSIMD, order,
) = _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, KIND_BISECT_THEN_SIMD, order)

# ---------------------------------------------------------------------------
# Specialized batched-Auto: pick a kind from the n/m ratio + linearity probe,
# then call the kind-parameterized sorted loop directly.
# ---------------------------------------------------------------------------

function _searchsortedlast_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        s::Auto, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    if _auto_is_uniform(v, s.props)
        @inbounds for k in eachindex(queries)
            idx_out[k] = search_last(KIND_UNIFORM_STEP, v, queries[k]; order = order)
        end
        return idx_out
    end
    m = length(queries)
    m == 0 && return idx_out
    if m == 1
        @inbounds idx_out[firstindex(idx_out)] =
            searchsortedlast(v, queries[firstindex(queries)], order)
        return idx_out
    end
    if !_take_sorted_path(queries, order, queries_sorted)
        return _searchsortedlast_unsorted_loop!(idx_out, v, queries, order)
    end
    gap, skewed = _estimate_avg_gap(v, queries, m)
    kind = _auto_batched_kind(v, s.props, gap, skewed, m)
    return _searchsortedlast_sorted_loop_kind!(idx_out, v, queries, kind, order)
end

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        s::Auto, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    if _auto_is_uniform(v, s.props)
        @inbounds for k in eachindex(queries)
            idx_out[k] = search_first(KIND_UNIFORM_STEP, v, queries[k]; order = order)
        end
        return idx_out
    end
    m = length(queries)
    m == 0 && return idx_out
    if m == 1
        @inbounds idx_out[firstindex(idx_out)] =
            searchsortedfirst(v, queries[firstindex(queries)], order)
        return idx_out
    end
    if !_take_sorted_path(queries, order, queries_sorted)
        return _searchsortedfirst_unsorted_loop!(idx_out, v, queries, order)
    end
    gap, skewed = _estimate_avg_gap(v, queries, m)
    kind = _auto_batched_kind(v, s.props, gap, skewed, m)
    return _searchsortedfirst_sorted_loop_kind!(idx_out, v, queries, kind, order)
end

# Batched Auto's kind picker: the v2 decision tree, returning a
# `StrategyKind` instead of branching to different loop specializations.
@inline function _auto_batched_kind(
        v::AbstractVector, props::SearchProperties, gap::Integer,
        skewed::Bool, m::Integer,
    )
    if gap <= _AUTO_BATCH_LINEAR_GAP
        return KIND_LINEAR_SCAN
    end
    if gap <= _auto_simd_gap_max(v) && _auto_simd_eligible(v, props)
        return KIND_SIMD_LINEAR_SCAN
    end
    if !skewed &&
            gap >= _AUTO_INTERP_MIN_GAP &&
            length(v) >= _AUTO_INTERP_MIN_N &&
            m >= _AUTO_INTERP_MIN_M &&
            _auto_interp_eligible(v, props, gap)
        return KIND_INTERPOLATION_SEARCH
    end
    if gap >= _AUTO_GALLOP_GAP_MIN
        return KIND_BRACKET_GALLOP
    end
    return KIND_EXP_FROM_LEFT
end

# ---------------------------------------------------------------------------
# Range search through the strategy dispatch
# ---------------------------------------------------------------------------

"""
    searchsortedrange(strategy, v, lo, hi[, hint]; order = Base.Order.Forward)
        -> UnitRange{Int}

Return the index range of all entries `v[i]` satisfying `lo ≤ v[i] ≤ hi`
under `order`. Equivalent to
`searchsortedfirst(strategy, v, lo[, hint]; order) :
 searchsortedlast(strategy, v, hi[, hint]; order)`.

When a `hint` is supplied it is used for both endpoint searches.
Strategies that ignore the hint treat the hinted form as a pass-through.
"""
@inline function searchsortedrange(
        strategy::SearchStrategy, v::AbstractVector, lo, hi;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    first_idx = searchsortedfirst(strategy, v, lo; order = order)
    last_idx = searchsortedlast(strategy, v, hi; order = order)
    return first_idx:last_idx
end

@inline function searchsortedrange(
        strategy::SearchStrategy, v::AbstractVector, lo, hi, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    first_idx = searchsortedfirst(strategy, v, lo, hint; order = order)
    last_idx = searchsortedlast(
        strategy, v, hi, max(first_idx, hint); order = order
    )
    return first_idx:last_idx
end

# Kind-tagged equivalent.
@inline function searchsortedrange(
        kind::StrategyKind, v::AbstractVector, lo, hi;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    first_idx = search_first(kind, v, lo; order = order)
    last_idx = search_last(kind, v, hi; order = order)
    return first_idx:last_idx
end

@inline function searchsortedrange(
        kind::StrategyKind, v::AbstractVector, lo, hi, hint::Integer;
        order::Base.Order.Ordering = Base.Order.Forward,
    )
    first_idx = search_first(kind, v, lo, hint; order = order)
    last_idx = search_last(kind, v, hi, max(first_idx, hint); order = order)
    return first_idx:last_idx
end

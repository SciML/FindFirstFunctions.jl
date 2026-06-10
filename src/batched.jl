# In-place batched sorted-search API: `searchsortedfirst!` / `searchsortedlast!`
# and `searchsortedrange`, plus the internal `_batched!` dispatchers and the
# Auto-specific specialization that turns Auto's decision tree into a single
# branchless dispatch on a concrete strategy.

"""
    searchsortedlast!(idx_out, v, queries; strategy = Auto(), order = Base.Order.Forward,
                       queries_sorted = nothing)

In-place batched `Base.searchsortedlast`. Writes one
index per element of `queries` into `idx_out` (which must be the same length).

If `queries` is sorted under `order`, the previous result is used as a hint for
the next query, so the total cost is O(length(v) + length(queries)) under
`strategy = BracketGallop()` (the default `Auto` choice for non-tiny `v`).

If `queries` is not sorted, falls back to per-element `searchsortedlast` with
no hint regardless of `strategy`.

The `queries_sorted` kwarg controls the runtime `issorted(queries)` check:

  - `nothing` (default): run `issorted(queries; order = order)` on every call.
    O(m) bookkeeping, roughly 1 ns/q on long batches.
  - `true`: trust the caller — skip the check and take the sorted-loop path
    unconditionally. Use this when you already know your queries are sorted
    (you computed them as a range, sorted them yourself, etc.). Wrong-answer
    risk: a non-sorted `queries` passed with `queries_sorted = true` will
    produce incorrect results, since the inner loop uses the previous result
    as a hint and that hint becomes invalid when queries jump backward.
  - `false`: skip the check and take the unsorted-loop path unconditionally
    (per-query unhinted `Base.searchsortedlast`). Use when you know queries
    are not sorted and want to avoid the O(m) probe.

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

In-place batched `Base.searchsortedfirst`. See
[`searchsortedlast!`](@ref) for behavior and for the `queries_sorted` kwarg.
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

# Sorted inner loop, parameterized on strategy. Used by both the generic and
# Auto batched entry points so each batch performs at most one issorted check.
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

# Decide whether to take the sorted-queries fast path. `queries_sorted` is
# the caller-supplied override: `nothing` means "check at runtime", `true`
# means "trust the caller, skip the O(m) issorted probe", `false` means
# "force the unsorted path".
@inline function _take_sorted_path(
        queries, order::Base.Order.Ordering, queries_sorted::Union{Nothing, Bool},
    )
    return queries_sorted === nothing ?
        issorted(queries; order = order) : queries_sorted
end

function _searchsortedlast_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    return if _take_sorted_path(queries, order, queries_sorted)
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
        s::Auto, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    # Uniform-spaced vectors (always true for `AbstractRange`, optionally
    # for `Vector`s carrying `SearchProperties(v; is_uniform = true)`) go
    # straight to the closed-form `UniformStep` path — no gap estimation,
    # no linearity probe, no `issorted` check (uniformly-spaced sorted
    # data has the same answer regardless of query ordering).
    if _auto_is_uniform(v, s.props)
        @inbounds for k in eachindex(queries)
            idx_out[k] = searchsortedlast(UniformStep(), v, queries[k]; order = order)
        end
        return idx_out
    end
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
    if !_take_sorted_path(queries, order, queries_sorted)
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
    # `DenseVector{Float64}` (without NaN).
    if gap <= _auto_simd_gap_max(v) && _auto_simd_eligible(v, s.props)
        return _searchsortedlast_sorted_loop!(
            idx_out, v, queries, SIMDLinearScan(), order
        )
    end
    # Sparse-on-large-linear: InterpolationSearch wins ~2× over ExpFromLeft
    # on uniformly-spaced data — but only when queries are *also* spread
    # roughly uniformly within their span.
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

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        strategy::SearchStrategy, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    return if _take_sorted_path(queries, order, queries_sorted)
        _searchsortedfirst_sorted_loop!(idx_out, v, queries, strategy, order)
    else
        _searchsortedfirst_unsorted_loop!(idx_out, v, queries, order)
    end
end

function _searchsortedfirst_batched!(
        idx_out, v::AbstractVector, queries::AbstractVector,
        s::Auto, order::Base.Order.Ordering,
        queries_sorted::Union{Nothing, Bool},
    )
    if _auto_is_uniform(v, s.props)
        @inbounds for k in eachindex(queries)
            idx_out[k] = searchsortedfirst(UniformStep(), v, queries[k]; order = order)
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
    if gap <= _AUTO_BATCH_LINEAR_GAP
        return _searchsortedfirst_sorted_loop!(
            idx_out, v, queries, LinearScan(), order
        )
    end
    if gap <= _auto_simd_gap_max(v) && _auto_simd_eligible(v, s.props)
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

# ---------------------------------------------------------------------------
# Range search through the strategy dispatch
# ---------------------------------------------------------------------------

"""
    searchsortedrange(strategy, v, lo, hi[, hint]; order = Base.Order.Forward)
        -> UnitRange{Int}

Return the index range of all entries `v[i]` satisfying `lo ≤ v[i] ≤ hi`
under `order`. Equivalent to
`searchsortedfirst(strategy, v, lo[, hint]; order) :
 searchsortedlast(strategy, v, hi[, hint]; order)` but expressed as a
single call that may share bracket-discovery work between the two
endpoints when the underlying strategy allows it.

The empty range case (no `v[i]` lies in `[lo, hi]`) returns
`searchsortedfirst(strategy, v, lo) : (searchsortedfirst(strategy, v, lo) - 1)`,
matching `Base.searchsorted(v, lo)` for an absent value.

When a `hint` is supplied it is used for both endpoint searches. Strategies
that ignore the hint (`BinaryBracket`, `InterpolationSearch`) treat the
hinted form as a pass-through.
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

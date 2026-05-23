# Sorted-search strategy type hierarchy. The singleton strategy structs
# (`LinearScan`, `BracketGallop`, …) exist for back-compat with v2's
# `Base.searchsortedlast(::S, ...)` API; the v3 preferred path is to call
# the enum-tagged `search_last` / `search_first` directly (see `kinds.jl`).
# The stateful strategies — `Auto` and `GuesserHint` — stay on the
# multimethod path because they carry per-instance data.

"""
    SearchStrategy

Abstract supertype for sorted-search strategies. Two flavours of
concrete subtype:

  - **Singleton strategies** (`LinearScan`, `SIMDLinearScan`,
    `BracketGallop`, `ExpFromLeft`, `InterpolationSearch`,
    `BitInterpolationSearch`, `BinaryBracket`, `UniformStep`,
    `BisectThenSIMD`) are zero-field structs. Each one has a matching
    `StrategyKind` enum value, and the v3 preferred entry point is
    [`search_last`](@ref) / [`search_first`](@ref) with that enum tag.
    The `Base.searchsortedlast(::S, ...)` API still works as a v2
    back-compat shim.
  - **Stateful strategies** (`Auto`, `GuesserHint`) carry per-instance
    data. They dispatch via their own `search_last` / `search_first`
    multimethods (and via `Base.searchsortedlast(::S, ...)` for
    back-compat).

Strategies can also be passed to the batched
[`searchsortedlast!`](@ref) / [`searchsortedfirst!`](@ref) APIs.
"""
abstract type SearchStrategy end

"""
    LinearScan <: SearchStrategy

Walk ±1 from the hint. Best when the target is within a few positions of the
hint. Falls back to [`BinaryBracket`](@ref) when no hint is supplied.

Maps to `KIND_LINEAR_SCAN`.
"""
struct LinearScan <: SearchStrategy end

"""
    SIMDLinearScan <: SearchStrategy

Variant of [`LinearScan`](@ref) whose forward walk is lowered to 8-wide
SIMD chunks via custom LLVM IR. Specialized for `DenseVector{Int64}` and
`DenseVector{Float64}`; for any other element type, falls back to plain
[`LinearScan`](@ref). The backward walk (when the hint is past the
answer) uses the scalar `LinearScan` path regardless of element type.

Maps to `KIND_SIMD_LINEAR_SCAN`.

Wins on long forward walks (≥ 8 elements past the hint). For walks of
1–3 elements `LinearScan` is comparable — the SIMD chunk has constant
setup overhead. Worst case is O(n / 8) which is still linear, so
`SIMDLinearScan` is only `Auto`-relevant for small `n` or small-gap
batches where plain `LinearScan` would have been picked anyway.

Caveats:
  - Element type must be exactly `Int64` or `Float64`.
  - Sorted-Float64 vectors containing `NaN` produce undefined results.
  - Falls back to [`BinaryBracket`](@ref) when no hint is supplied.
  - Falls back to [`LinearScan`](@ref) for non-`Forward` orderings.
"""
struct SIMDLinearScan <: SearchStrategy end

"""
    BracketGallop <: SearchStrategy

Expand an exponential bracket bidirectionally from the hint, then
binary-search inside the bracket. Effectively O(1) when the target is near
the hint; never worse than ~2 log₂ n comparisons.

Maps to `KIND_BRACKET_GALLOP`. Falls back to [`BinaryBracket`](@ref) when
no hint is supplied.
"""
struct BracketGallop <: SearchStrategy end

"""
    ExpFromLeft <: SearchStrategy

Exponential search forward from the hint (interpreted as a left bound), then
binary search in the final bracket. Best for batched sorted queries where
each next query's hint is the previous result.

Maps to `KIND_EXP_FROM_LEFT`. Falls back to [`BinaryBracket`](@ref) when
no hint is supplied.
"""
struct ExpFromLeft <: SearchStrategy end

"""
    InterpolationSearch <: SearchStrategy

Guesses an index by linearly extrapolating `x` between `v[lo]` and `v[hi]`,
then refines with a bounded binary search.

Maps to `KIND_INTERPOLATION_SEARCH`. Ignores any hint. Falls back to
[`BinaryBracket`](@ref) for non-numeric element types.
"""
struct InterpolationSearch <: SearchStrategy end

"""
    BitInterpolationSearch <: SearchStrategy

Variant of [`InterpolationSearch`](@ref) that reinterprets `DenseVector{Float64}`
as `DenseVector{UInt64}` before computing the extrapolation guess. Wins on
log-spaced (geometric) data.

Maps to `KIND_BIT_INTERPOLATION_SEARCH`.

Constraints:
  - `DenseVector{Float64}` only.
  - Requires `v[1] > 0` and the query `x > 0`.
  - Forward / Reverse orderings only.

**Opt-in only** — `Auto` does not pick this strategy. Falls back to
[`InterpolationSearch`](@ref) for non-Float64 dense eltypes, and to
[`BinaryBracket`](@ref) for non-positive or non-finite Float64 data.
"""
struct BitInterpolationSearch <: SearchStrategy end

"""
    BinaryBracket <: SearchStrategy

Plain `Base.searchsortedlast` / `Base.searchsortedfirst`. Ignores any hint.

Maps to `KIND_BINARY_BRACKET`.
"""
struct BinaryBracket <: SearchStrategy end

"""
    UniformStep <: SearchStrategy

O(1) direct-arithmetic lookup for uniformly-spaced vectors.

Maps to `KIND_UNIFORM_STEP`. Specialized for `AbstractRange{<:Real}`; for
other vector types, falls back to [`BinaryBracket`](@ref). Ignores any hint.
"""
struct UniformStep <: SearchStrategy end

"""
    BisectThenSIMD <: SearchStrategy

Equality-search strategy. Binary-bisects `v` down to a small basecase,
then SIMD-scans the basecase for exact equality with `x`. Specialised for
`DenseVector{Int64}` + `Int64` queries.

Maps to `KIND_BISECT_THEN_SIMD`. Meant for use with [`findequal`](@ref
FindFirstFunctions.findequal), not with `searchsortedfirst` /
`searchsortedlast` — in the positional API it falls back to
[`BinaryBracket`](@ref).
"""
struct BisectThenSIMD <: SearchStrategy end

"""
    GuesserHint(guesser::Guesser) <: SearchStrategy

Uses a [`Guesser`](@ref) to produce an integer guess for `x`, then
dispatches to [`BracketGallop`](@ref) from that guess. The `Guesser`
already decides between linear-extrapolation lookup and using the
previous result as a guess; this strategy plugs that logic into the
strategy dispatch hierarchy.

**Stateful strategy.** `GuesserHint` carries the `Guesser` (which carries
`idx_prev::Ref{Int}` and `linear_lookup::Bool`), so it cannot be reduced
to a `StrategyKind` tag. It dispatches via its own
`search_last(::GuesserHint, ...)` / `search_first(::GuesserHint, ...)`
methods.

Use this strategy with the per-query and batched APIs whenever you have a
`Guesser` attached to a vector.
"""
struct GuesserHint{G} <: SearchStrategy
    guesser::G
end

"""
    SearchProperties{T}

Cached, non-allocating facts about a sorted vector. Pass to [`Auto`](@ref)
via `Auto(props)` to skip the per-call probes that the default `Auto()` runs
on every batched call.

Default-constructed (`SearchProperties()`) is the "no information" sentinel:
`has_props` is `false`, the other fields are unspecified and ignored by
`Auto`. Construct via `SearchProperties(v::AbstractVector)` to populate the
fields by running the probes once.

`T` is the **data ratio type** — the type of `oneunit(eltype(v)) /
oneunit(eltype(v))`, so e.g. `SearchProperties{Float64}` for
`Vector{Int}` (because `Int/Int` promotes to `Float64`) or `Vector{Float64}`,
`SearchProperties{Float32}` for `Vector{Float32}`. For non-`Number` eltypes
the default is `Float64` and `has_props = false`.

Currently consumed by `Auto`:

  - `is_linear` — gates `InterpolationSearch` in batched dispatch.
  - `has_nan` (Float64 only) — gates `SIMDLinearScan` eligibility.
  - `is_uniform` — short-circuits to [`UniformStep`](@ref) when set, with
    `first_val` and `inv_step` baked in for closed-form O(1) lookup.

When `is_uniform = true`, `first_val` and `inv_step` hold the precomputed
data needed by `UniformStep`'s closed-form path
(`idx = floor((x - first_val) * inv_step) + 1`). When `is_uniform = false`
they are `zero(T)` and never consulted.

The `is_log_linear` field is populated for callers that want to manually
pin [`BitInterpolationSearch`](@ref); `Auto` does not consume it.
"""
struct SearchProperties{T}
    has_props::Bool
    is_linear::Bool
    has_nan::Bool
    is_log_linear::Bool
    is_uniform::Bool
    first_val::T
    inv_step::T
end

# Data ratio type used by SearchProperties{T}: `1/oneunit(eltype(v))` promotion.
# `Int → Float64`, `Float64 → Float64`, `Float32 → Float32`.
@inline _ratio_type(::Type{T}) where {T <: AbstractFloat} = T
@inline _ratio_type(::Type{T}) where {T <: Number} = typeof(oneunit(T) / oneunit(T))
@inline _ratio_type(::Type) = Float64

SearchProperties() = SearchProperties{Float64}(
    false, false, false, false, false, 0.0, 0.0,
)

"""
    Auto <: SearchStrategy
    Auto()
    Auto(props::SearchProperties)
    Auto(v::AbstractVector)
    Auto(v::AbstractVector, props::SearchProperties)

Stateful strategy that resolves to a concrete [`StrategyKind`](@ref) at
construction time. The resolution uses static information available at
construction: `props` (if supplied) plus `v` (if supplied).

**Per-query** (`search_last(Auto(), v, x[, hint])` or the legacy
`searchsortedlast(Auto(), v, x[, hint])`): forwards directly to the
stored kind. `Auto()` defaults to `KIND_BINARY_BRACKET` (safe choice
when nothing is known about `v`); `Auto(v)` resolves to a faster kind
based on `length(v)`, `props.is_uniform`, etc. Callers that want the
v2-era "pick at every query based on length and hint" behaviour should
explicitly construct `Auto(v)` for each new `v`.

**Batched sorted** (`searchsortedlast!(out, v, queries; strategy = Auto())`):
the batched dispatcher re-resolves the kind from `(v, queries)` even
when `Auto()` carries the default kind — the gap-based decision tree
requires the queries, which aren't available at Auto-construction time.

**Cached properties.** Passing a populated [`SearchProperties`](@ref) via
`Auto(props)` or `Auto(v, props)` short-circuits the per-call probes. The
cached path is behaviour-equivalent to `Auto(v)` when `props` is up to
date for `v`; the caller is responsible for re-computing `props` if `v`
mutates.

# Fields

  - `kind::StrategyKind` — resolved kind. Use this field directly in
    hot loops via `search_last(auto.kind, v, x, hint)` to skip the
    `auto.props` field load entirely.
  - `props::SearchProperties` — cached properties used by the batched
    decision tree.
"""
struct Auto{T} <: SearchStrategy
    kind::StrategyKind
    props::SearchProperties{T}
end

Auto() = Auto{Float64}(KIND_BINARY_BRACKET, SearchProperties())
Auto(props::SearchProperties{T}) where {T} =
    Auto{T}(_default_kind_from_props(props), props)
Auto(v::AbstractVector) = Auto(v, SearchProperties(v))
function Auto(v::AbstractVector, props::SearchProperties{T}) where {T}
    return Auto{T}(_auto_resolve_kind(v, props), props)
end

# When props alone is available (no `v`), the best we can do is pick
# `UniformStep` if `props.is_uniform`. Otherwise fall back to the safe
# default.
@inline function _default_kind_from_props(props::SearchProperties)
    return props.has_props && props.is_uniform ?
        KIND_UNIFORM_STEP : KIND_BINARY_BRACKET
end

# Per-query Auto resolution: when v is known. Concrete `_auto_resolve_kind`
# logic lives in `auto.jl` — these forward-declared symbols are looked up
# lazily at call time, so the include order works out.
function _auto_resolve_kind end

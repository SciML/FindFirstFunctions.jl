# Sorted-search strategy type hierarchy. All concrete strategies live here;
# their `Base.searchsortedfirst` / `Base.searchsortedlast` method definitions
# live in `dispatch.jl` and `auto.jl`. The `SearchProperties` cache type
# is defined here too because `Auto` carries one as a field; its populated
# constructor lives in `search_properties.jl`.

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
  - [`LinearBinarySearch`](@ref) walks linearly from the hint for up to `MAX`
    steps then falls back to a binary search. Wins at small constant gaps
    where the exponential-doubling overhead of `ExpFromLeft` /
    `BracketGallop` is pure cost.
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
    LinearBinarySearch{MAX}() <: SearchStrategy
    LinearBinarySearch()                       # default MAX = 8
    LinearBinarySearch(linear_window::Integer) # curated MAX from {0, 1, 2, 4, 8, 16, 32, 64, 128}

Bounded linear walk from the hint, falling back to [`BinaryBracket`](@ref)
when the answer isn't found within `MAX` steps. Designed for workloads where
consecutive queries are *probably* within a small constant gap of the
previous result — the linear walk's tight per-step cost beats the exponential
doubling overhead of [`ExpFromLeft`](@ref) / [`BracketGallop`](@ref) at small
gaps, while the binary fallback caps the worst case at `O(log n)` after the
`MAX` linear probes.

Per-call cost decomposes as:

  - `O(min(gap, MAX))` scalar comparisons when the answer is within `MAX` of
    the hint (the common case for monotone-forward ODE-style sweeps),
  - `MAX` scalar comparisons plus one full `searchsortedlast` /
    `searchsortedfirst` binary search when the answer is farther away.

`MAX` is a *type parameter*, not a runtime field — the walk count is
statically known and the unrolled loop body is fully inlined. Allowed values
are `0, 1, 2, 4, 8, 16, 32, 64, 128`; arbitrary integers would cause a
specialization explosion, so the factory constructor restricts to a curated
set. Construct as `LinearBinarySearch()` for the default (`MAX = 8`),
`LinearBinarySearch(k)` for a specific `k`, or `LinearBinarySearch{k}()` for
the parametric form directly.

Comparison with neighbour strategies:

  - vs [`LinearScan`](@ref): same walk semantics from the hint, but bounded
    by `MAX` with a binary fallback rather than walking all the way to the
    boundary. Strictly better when the hint may occasionally be far off; the
    `MAX = 0` form degenerates to a single hint-position check.
  - vs [`ExpFromLeft`](@ref): no doubling overhead. ExpFromLeft does ≥ 5
    initial linear probes plus exponential expansion; at very small gaps
    (≤ 4) those expansion checks are pure overhead, and at moderate gaps
    (≤ MAX) the linear walk wins on cache locality.
  - vs [`BracketGallop`](@ref): walks linearly rather than bidirectionally
    doubling. Wins when the hint is reliably *behind* the answer; loses
    when the hint is past the answer and `MAX` is small (a backward walk
    of `MAX` steps may not be enough; bracket gallop's exponential expansion
    handles backward-far hints natively).

Falls back to [`BinaryBracket`](@ref) when no hint is supplied (the linear
walk has no anchor) and when `hint` is outside `axes(v)`.
"""
struct LinearBinarySearch{MAX} <: SearchStrategy end
LinearBinarySearch() = LinearBinarySearch{8}()

# Curated MAX values — arbitrary integers would cause per-MAX method
# specialization explosion across the dispatch table. The set covers the
# practical sweet spot for ODE-style monotone-forward workloads (small MAX)
# through to wide-jitter or very-large-n workloads (large MAX). 0 is a valid
# choice — it means "check the hint position and immediately fall through
# to binary search if it's not the answer", useful for callers who want
# explicit no-walk semantics.
function LinearBinarySearch(linear_window::Integer)
    linear_window == 0 && return LinearBinarySearch{0}()
    linear_window == 1 && return LinearBinarySearch{1}()
    linear_window == 2 && return LinearBinarySearch{2}()
    linear_window == 4 && return LinearBinarySearch{4}()
    linear_window == 8 && return LinearBinarySearch{8}()
    linear_window == 16 && return LinearBinarySearch{16}()
    linear_window == 32 && return LinearBinarySearch{32}()
    linear_window == 64 && return LinearBinarySearch{64}()
    linear_window == 128 && return LinearBinarySearch{128}()
    throw(
        ArgumentError(
            "`linear_window` must be one of (0, 1, 2, 4, 8, 16, 32, 64, 128), got $linear_window",
        ),
    )
end

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
    BitInterpolationSearch <: SearchStrategy

Variant of [`InterpolationSearch`](@ref) that reinterprets `DenseVector{Float64}`
as `DenseVector{UInt64}` before computing the extrapolation guess. For
positive IEEE Float64 values, the bit pattern is monotonically increasing
with the float value and is approximately linear in array index when the
underlying data is *log-spaced* (geometric). On such data the bit-domain
guess is far better than the float-domain guess that `InterpolationSearch`
would compute — sometimes O(1) versus O(log n) refinement.

After computing the bit-domain guess, the bracket and binary refine step
uses the original float values for comparison, so the answer is identical
to `Base.searchsortedlast` / `Base.searchsortedfirst`.

Constraints:
  - `DenseVector{Float64}` only (the IEEE bit-pattern trick is Float64-specific).
  - Requires `v[1] > 0` and the query `x > 0` (negative, zero, subnormal,
    and non-finite Float64 bit patterns are not monotonic with float value
    under raw reinterpret).
  - Forward ordering only.

**This strategy is opt-in only** — `Auto` does not pick it. The bench sweep
shows the per-query division and UInt64↔Float64 conversion overhead
(~60–90 ns/q) costs more than the bracket refinement that the guess
saves at every gap tested; pinning `BitInterpolationSearch` is slower than
letting `Auto` pick `SIMDLinearScan` / `BracketGallop` / `ExpFromLeft`.
The strategy is retained for users with workloads not covered by the
sweep — for instance, very-large `n` (≥ 2²⁰), pathologically log-spaced
data, or hardware where Float64 division is unusually cheap relative to
the scalar walk.

Falls back to [`InterpolationSearch`](@ref) for non-Float64 dense eltypes
(where the bit pattern equals the value and the two strategies are
equivalent), and to [`BinaryBracket`](@ref) for non-positive or
non-finite Float64 data.
"""
struct BitInterpolationSearch <: SearchStrategy end

"""
    BinaryBracket <: SearchStrategy

Plain `Base.searchsortedlast` / `Base.searchsortedfirst`. Ignores any hint
that is supplied.
"""
struct BinaryBracket <: SearchStrategy end

"""
    UniformStep <: SearchStrategy

O(1) direct-arithmetic lookup for uniformly-spaced vectors. The answer
index is computed from `(x - first(v)) / step(v)` rather than via binary
search or galloping — independent of `length(v)`.

Specialized for `AbstractRange{<:Real}` (where `step(v)` is well-defined
and the spacing is exact). For other vector types, falls back to
[`BinaryBracket`](@ref). For non-`Forward` / non-`Reverse` orderings,
also falls back to [`BinaryBracket`](@ref).

Auto automatically dispatches to `UniformStep` when `v isa AbstractRange`,
so callers passing a range to `searchsortedlast(Auto(), r, x)` get the
O(1) path with no per-call probe overhead.

Ignores any hint that is supplied — the closed form doesn't benefit from
a hint.
"""
struct UniformStep <: SearchStrategy end

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

Currently consumed by `Auto`:

  - `is_linear` — gates `InterpolationSearch` in batched dispatch.
  - `has_nan` (Float64 only) — gates `SIMDLinearScan` eligibility.
  - `is_uniform` — short-circuits to [`UniformStep`](@ref) (closed-form
    O(1) lookup) when set. Automatically `true` for
    `SearchProperties(::AbstractRange)`; callers with a `Vector` that
    they know to be exactly uniformly-spaced can construct
    `SearchProperties(v; is_uniform = true)` to opt into the same fast
    path.

The `is_log_linear` field is populated for callers that want to manually
pin [`BitInterpolationSearch`](@ref) based on data shape; `Auto` does not
consume it. Remaining fields are populated for forward compatibility.
"""
struct SearchProperties
    has_props::Bool
    is_linear::Bool
    has_nan::Bool
    is_log_linear::Bool
    is_uniform::Bool
end

SearchProperties() = SearchProperties(false, false, false, false, false)

"""
    Auto <: SearchStrategy
    Auto()
    Auto(props::SearchProperties)

Heuristically picks among [`LinearScan`](@ref), [`SIMDLinearScan`](@ref),
[`ExpFromLeft`](@ref), [`InterpolationSearch`](@ref),
[`BracketGallop`](@ref), and [`BinaryBracket`](@ref). The choice depends on
the calling context:

**Per-query** (`searchsortedlast(Auto(), v, x[, hint])`):
  - No hint, or hint outside `axes(v)` → [`BinaryBracket`](@ref).
  - Hint in range, `length(v) ≤ 16` → [`LinearScan`](@ref).
  - Hint in range, `length(v) > 16` → [`BracketGallop`](@ref).

**Batched sorted** (`searchsortedlast!(out, v, queries; strategy = Auto())`)
chooses by the expected average gap in `v`'s index space between
consecutive query results. See the package's `auto.md` documentation for
the full decision tree and the crossover constants the bench sweep
determined.

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

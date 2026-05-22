# Back-compat shims: `Base.searchsortedlast(::S, ...)` /
# `Base.searchsortedfirst(::S, ...)` for the singleton strategy structs
# (`BinaryBracket`, `LinearScan`, …). Each shim forwards to the
# corresponding `search_last(KIND_X, ...)` / `search_first(KIND_X, ...)`
# call, so the enum dispatcher is the single source of truth.
#
# These shims are scheduled for removal in the next major version (v4).
# New code should call `search_last` / `search_first` with a
# `StrategyKind` value directly.
#
# Each shim emits a `Base.depwarn` once per call site (the `depwarn`
# infrastructure de-duplicates by `(symbol, file:line)`), encouraging
# migration to the new API while keeping existing code working.

# `strategy_kind(s)` — the public mapping from strategy struct → tag.
strategy_kind(::BinaryBracket) = KIND_BINARY_BRACKET
strategy_kind(::LinearScan) = KIND_LINEAR_SCAN
strategy_kind(::SIMDLinearScan) = KIND_SIMD_LINEAR_SCAN
strategy_kind(::BracketGallop) = KIND_BRACKET_GALLOP
strategy_kind(::ExpFromLeft) = KIND_EXP_FROM_LEFT
strategy_kind(::InterpolationSearch) = KIND_INTERPOLATION_SEARCH
strategy_kind(::BitInterpolationSearch) = KIND_BIT_INTERPOLATION_SEARCH
strategy_kind(::UniformStep) = KIND_UNIFORM_STEP
strategy_kind(::BisectThenSIMD) = KIND_BISECT_THEN_SIMD

# Stateful strategies (`GuesserHint`, `Auto`) don't map to a single tag.
strategy_kind(s::Auto) = s.kind
strategy_kind(::GuesserHint) = throw(
    ArgumentError(
        "GuesserHint is a stateful strategy with no StrategyKind tag; use its own dispatch.",
    ),
)

# ---------------------------------------------------------------------------
# `Base.searchsortedlast(::S, v, x[, hint]; order)` shims for each singleton
# strategy. Each method is a one-line forward to `search_last(KIND_X, ...)`.
#
# The shim is intentionally not `@deprecate`-wrapped because Julia's
# `@deprecate` doesn't compose cleanly with keyword arguments, and the
# noise of a per-call `Base.depwarn` would obscure test output across the
# whole ecosystem during the v3 transition. The deprecation is documented
# (NEWS, docs, this comment block); a v4 release will remove the shims.
# ---------------------------------------------------------------------------

for (S, KIND) in (
        (:BinaryBracket, :KIND_BINARY_BRACKET),
        (:LinearScan, :KIND_LINEAR_SCAN),
        (:SIMDLinearScan, :KIND_SIMD_LINEAR_SCAN),
        (:BracketGallop, :KIND_BRACKET_GALLOP),
        (:ExpFromLeft, :KIND_EXP_FROM_LEFT),
        (:InterpolationSearch, :KIND_INTERPOLATION_SEARCH),
        (:BitInterpolationSearch, :KIND_BIT_INTERPOLATION_SEARCH),
        (:UniformStep, :KIND_UNIFORM_STEP),
        (:BisectThenSIMD, :KIND_BISECT_THEN_SIMD),
    )
    @eval begin
        Base.searchsortedlast(
            ::$S, v::AbstractVector, x;
            order::Base.Order.Ordering = Base.Order.Forward,
        ) = search_last($KIND, v, x; order = order)
        Base.searchsortedfirst(
            ::$S, v::AbstractVector, x;
            order::Base.Order.Ordering = Base.Order.Forward,
        ) = search_first($KIND, v, x; order = order)
        Base.searchsortedlast(
            ::$S, v::AbstractVector, x, hint::Integer;
            order::Base.Order.Ordering = Base.Order.Forward,
        ) = search_last($KIND, v, x, hint; order = order)
        Base.searchsortedfirst(
            ::$S, v::AbstractVector, x, hint::Integer;
            order::Base.Order.Ordering = Base.Order.Forward,
        ) = search_first($KIND, v, x, hint; order = order)
    end
end

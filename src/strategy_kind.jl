# Strategy structs as values: the `strategy_kind` mapping from a strategy
# struct to its `StrategyKind` tag, plus `searchsorted_last` / `searchsorted_first`
# methods that accept a singleton strategy struct directly and forward
# through the mapping. For a literal strategy argument
# (`searchsorted_last(BracketGallop(), v, x, hint)`) the mapping constant-folds,
# so the struct form costs nothing over the kind form.
#
# v3 does not extend `Base.searchsortedlast` / `Base.searchsortedfirst`
# with strategy methods — `searchsorted_last` / `searchsorted_first` are the only
# search entry points.

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

# Parametric strategies (`LinearBinarySearch{MAX}`) don't map to a single
# tag either: no one enum value can represent every `MAX`. They dispatch
# via the struct multimethods below, which specialize on the type
# parameter exactly like the singleton struct form constant-folds.
strategy_kind(::LinearBinarySearch) = throw(
    ArgumentError(
        "LinearBinarySearch{MAX} is parametric and has no StrategyKind tag; pass the struct directly.",
    ),
)

# Struct-valued entry points. `Auto` and `GuesserHint` define their own,
# more specific `searchsorted_last` / `searchsorted_first` methods (in `auto.jl` and
# `guesser.jl`), so this fallback only ever sees the zero-state singletons.
@inline searchsorted_last(
    s::SearchStrategy, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_last(strategy_kind(s), v, x; order = order)
@inline searchsorted_first(
    s::SearchStrategy, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_first(strategy_kind(s), v, x; order = order)
@inline searchsorted_last(
    s::SearchStrategy, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_last(strategy_kind(s), v, x, hint; order = order)
@inline searchsorted_first(
    s::SearchStrategy, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) = searchsorted_first(strategy_kind(s), v, x, hint; order = order)

# LinearBinarySearch struct entry points. `MAX` rides the type parameter
# into the kernel, so a literal `LinearBinarySearch{k}()` compiles to the
# same specialized code as the v2 `Base.searchsortedlast(::LinearBinarySearch{k}, ...)`
# methods did. No hint (or, inside the kernel, an out-of-range hint) falls
# through to the plain binary search — the linear walk has no anchor.
@inline searchsorted_last(
    ::LinearBinarySearch{MAX}, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) where {MAX} = _kernel_last_linear_binary_search(v, x, hint, order, Val(MAX))
@inline searchsorted_first(
    ::LinearBinarySearch{MAX}, v::AbstractVector, x, hint::Integer;
    order::Base.Order.Ordering = Base.Order.Forward,
) where {MAX} = _kernel_first_linear_binary_search(v, x, hint, order, Val(MAX))
@inline searchsorted_last(
    ::LinearBinarySearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = _kernel_last_binary_bracket(v, x, order)
@inline searchsorted_first(
    ::LinearBinarySearch, v::AbstractVector, x;
    order::Base.Order.Ordering = Base.Order.Forward,
) = _kernel_first_binary_bracket(v, x, order)

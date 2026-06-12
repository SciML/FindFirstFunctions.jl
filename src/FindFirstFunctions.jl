module FindFirstFunctions

# Public API surface for `using FindFirstFunctions`. The strategy types are
# zero-field singletons (except `GuesserHint` and `Auto`, which carry
# small isbits payloads), so exporting them only adds names to the
# caller's namespace — no runtime cost.
#
# v3 replaces the v2 `Base.searchsortedlast(::S, ...)` extensions with
# the FFF-owned `search_last` / `search_first` dispatchers, which accept
# a `StrategyKind` tag, a strategy struct, or a stateful strategy
# (`Auto`, `GuesserHint`). FFF no longer extends `Base.searchsortedlast`
# or `Base.searchsortedfirst`.
export
    # Abstract type + concrete singleton strategies (friendly strategy values).
    SearchStrategy,
    LinearScan, SIMDLinearScan, BracketGallop, ExpFromLeft,
    InterpolationSearch, BitInterpolationSearch,
    BinaryBracket, UniformStep, BisectThenSIMD,
    # Stateful strategies.
    GuesserHint, Auto,
    # Properties / helpers.
    SearchProperties,
    Guesser, looks_linear,
    # Enum + dispatchers (v3 preferred path).
    StrategyKind,
    KIND_BINARY_BRACKET, KIND_LINEAR_SCAN, KIND_SIMD_LINEAR_SCAN,
    KIND_BRACKET_GALLOP, KIND_EXP_FROM_LEFT,
    KIND_INTERPOLATION_SEARCH, KIND_BIT_INTERPOLATION_SEARCH,
    KIND_UNIFORM_STEP, KIND_BISECT_THEN_SIMD,
    search_last, search_first, strategy_kind,
    # Batched API.
    searchsortedfirst!, searchsortedlast!, searchsortedrange,
    # Equality search.
    findequal, findfirstequal, findfirstsortedequal

# Julia 1.12 changed how `Ptr{T}` arguments to `Base.llvmcall` are passed.
const USE_PTR = VERSION >= v"1.12.0-DEV.255"

# Source layout. Include order matters — each file may depend on names
# defined in earlier files.
include("simd_ir.jl")             # IR template + SIMD primitives
include("equality.jl")            # findfirstequal + findfirstsortedequal
include("kinds.jl")               # StrategyKind enum + search_last / search_first dispatchers
include("strategies.jl")          # SearchStrategy + concrete strategy types + SearchProperties + Auto
include("search_properties.jl")   # Linearity / NaN probes + populated SearchProperties constructor
include("kernels.jl")             # Per-strategy kernel functions called by the dispatchers
include("strategy_kind.jl")       # strategy struct → kind mapping + struct-valued search entry points
include("auto.jl")                # Auto helpers + _auto_resolve_kind + Auto dispatch
include("batched.jl")             # Batched API + Auto batched specialization
include("guesser.jl")             # looks_linear + Guesser + GuesserHint dispatch
include("findequal.jl")           # findequal + BisectThenSIMD shortcut
include("precompile.jl")          # PrecompileTools workload

end # module FindFirstFunctions

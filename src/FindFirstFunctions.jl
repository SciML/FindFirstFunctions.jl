module FindFirstFunctions

# Public API surface for `using FindFirstFunctions`. The strategy types are
# zero-field singletons (except `GuesserHint` and `Auto`, which carry
# small isbits payloads), so exporting them only adds names to the
# caller's namespace — no runtime cost.
#
# v3 introduces the enum-tagged dispatch path (`search_last` /
# `search_first` over `StrategyKind` values). The v2
# `Base.searchsortedlast(::S, ...)` API remains as a back-compat shim,
# scheduled for removal in v4.
export
    # Abstract type + concrete singleton strategies (v2 back-compat).
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
include("legacy_dispatch.jl")     # Base.searchsortedlast(::S,…) back-compat shims + strategy_kind
include("auto.jl")                # Auto helpers + _auto_resolve_kind + Auto dispatch
include("batched.jl")             # Batched API + Auto batched specialization
include("guesser.jl")             # looks_linear + Guesser + GuesserHint dispatch
include("findequal.jl")           # findequal + BisectThenSIMD shortcut
include("precompile.jl")          # PrecompileTools workload

end # module FindFirstFunctions

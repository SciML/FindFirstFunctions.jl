module FindFirstFunctions

# Public API surface for `using FindFirstFunctions`. The strategy types are
# zero-field singletons (except `GuesserHint` and `Auto`, which carry small
# isbits payloads), so exporting them only adds names to the caller's
# namespace — no runtime cost. `searchsortedfirst!` / `searchsortedlast!`
# are FFF-defined names (the non-bang `searchsortedfirst` /
# `searchsortedlast` are extensions of `Base` and are reachable without
# qualification once `Base` is in scope).
export
    SearchStrategy,
    LinearScan, SIMDLinearScan, BracketGallop, ExpFromLeft,
    InterpolationSearch, BitInterpolationSearch,
    BinaryBracket, BisectThenSIMD,
    GuesserHint, Auto,
    SearchProperties,
    Guesser, looks_linear,
    searchsortedfirst!, searchsortedlast!, searchsortedrange,
    findequal, findfirstequal, findfirstsortedequal

# Julia 1.12 changed how `Ptr{T}` arguments to `Base.llvmcall` are passed:
# they're now real pointers rather than i64s. https://github.com/JuliaLang/julia/pull/53687
const USE_PTR = VERSION >= v"1.12.0-DEV.255"

# Source layout. Include order matters — each file may depend on names
# defined in earlier files. See the comment block at the top of each file
# for what lives where.
include("simd_ir.jl")             # IR template + per-eltype IR constants + SIMD primitives
include("equality.jl")            # findfirstequal + findfirstsortedequal
include("strategies.jl")          # SearchStrategy + concrete strategy types + SearchProperties + Auto
include("search_properties.jl")   # Linearity / NaN probes + populated SearchProperties constructor
include("dispatch.jl")            # Per-strategy searchsortedfirst/last methods + their internal helpers
include("auto.jl")                # Auto crossover constants + per-query Auto + Auto's batched helpers
include("batched.jl")             # Batched API + searchsortedrange + _batched! (incl Auto specialization)
include("guesser.jl")             # looks_linear + Guesser + GuesserHint dispatch
include("findequal.jl")           # findequal + BisectThenSIMD shortcut
include("precompile.jl")          # PrecompileTools workload

end # module FindFirstFunctions

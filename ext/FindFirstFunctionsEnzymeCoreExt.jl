module FindFirstFunctionsEnzymeCoreExt

using FindFirstFunctions
using EnzymeCore: EnzymeRules

# Every FindFirstFunctions entry point answers a *where* question: it returns an
# index (or `nothing`), or writes indices into an integer buffer. Its arguments
# enter only through comparisons, so no derivative flows through the call in
# either direction. Marking the entry points `inactive` tells Enzyme exactly
# that: run the primal, propagate nothing. This is exact, not an approximation.
#
# It also matters for codegen. The early-exit search loops emit
# `gc_preserve_begin`/`gc_preserve_end` token pairs that Enzyme's reverse pass
# cannot yet reorder (EnzymeAD/Enzyme.jl#3404 — "Instruction does not dominate
# all uses!", a hard LLVM verifier abort). Without this rule any reverse-mode
# differentiation of code that looks up an interpolation interval with
# `searchsorted_last`, e.g. DataInterpolations through an ODE right-hand side,
# aborts the process even though the search itself carries no derivative.
for f in (
        searchsorted_last, searchsorted_first,
        searchsortedlast!, searchsortedfirst!, searchsortedrange,
        findequal, findfirstequal, findfirstsortedequal,
    )
    @eval EnzymeRules.inactive(::typeof($f), args...; kwargs...) = nothing
end

end

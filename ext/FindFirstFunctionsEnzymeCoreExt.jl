module FindFirstFunctionsEnzymeCoreExt

using FindFirstFunctions
using EnzymeCore: EnzymeRules

for f in (
        searchsorted_last, searchsorted_first,
        searchsortedlast!, searchsortedfirst!, searchsortedrange,
        findequal, findfirstequal, findfirstsortedequal,
    )
    @eval EnzymeRules.inactive(::typeof($f), args...; kwargs...) = nothing
end

end

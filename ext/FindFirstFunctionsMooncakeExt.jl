module FindFirstFunctionsMooncakeExt

using FindFirstFunctions
using Mooncake: Mooncake, @is_primitive, @zero_derivative, CoDual, Dual, MinimalCtx, NoPullback, primal, zero_dual, zero_fcodual
import Mooncake: frule!!, rrule!!

# These functions all return a discrete index (or a batch of indices) locating a value
# within a sorted/searched collection: the result has no meaningful derivative. Same
# position as `EnzymeRules.inactive` already takes for this exact list of functions -- see
# `FindFirstFunctionsEnzymeCoreExt`.
#
# For Mooncake specifically, this also works around a real translation limitation:
# `searchsorted_first`/`searchsorted_last`'s `KIND_SIMD_LINEAR_SCAN` strategy embeds a
# hand-written SIMD kernel via a raw `Core.Intrinsics.llvmcall`, which Mooncake's
# intrinsic-lifting machinery cannot translate (arbitrary embedded LLVM IR text has no
# general translation). Marking the dispatcher itself `@zero_derivative` -- rather than
# patching the SIMD kernel -- stops Mooncake before it ever descends into that (or any
# other strategy's) kernel. Surfaced via native Hessian-vector products through
# `OrdinaryDiffEq`'s dense-output interpolation: see
# https://github.com/SciML/SciMLSensitivity.jl/issues/1648.
const _INACTIVE_FNS = (
    FindFirstFunctions.searchsorted_last,
    FindFirstFunctions.searchsorted_first,
    FindFirstFunctions.searchsortedlast!,
    FindFirstFunctions.searchsortedfirst!,
    FindFirstFunctions.searchsortedrange,
    FindFirstFunctions.findequal,
    FindFirstFunctions.findfirstequal,
    FindFirstFunctions.findfirstsortedequal,
)

for f in _INACTIVE_FNS
    @eval @zero_derivative MinimalCtx Tuple{typeof($f),Vararg}
end

const _InactiveFn = Union{map(typeof, _INACTIVE_FNS)...}

# Keyword arguments (`order`, `strategy`, `queries_sorted`, ...) are reached through the
# compiler-generated keyword-body method via `Core.kwcall`, not the plain signature above,
# so give that entry point the same treatment. The primal call must still go through
# `Core.kwcall` itself so that a non-default keyword is honoured -- only the derivative is
# zero here.
@is_primitive MinimalCtx Tuple{typeof(Core.kwcall),NamedTuple,F,Vararg} where {F<:_InactiveFn}

function frule!!(
    ::Dual{typeof(Core.kwcall)},
    kwargs::Dual{<:NamedTuple},
    f::Dual{<:_InactiveFn},
    args::Vararg{Dual},
)
    y = Core.kwcall(primal(kwargs), primal(f), map(primal, args)...)
    return zero_dual(y)
end

function rrule!!(
    kwcall::CoDual{typeof(Core.kwcall)},
    kwargs::CoDual{<:NamedTuple},
    f::CoDual{<:_InactiveFn},
    args::Vararg{CoDual},
)
    y = Core.kwcall(primal(kwargs), primal(f), map(primal, args)...)
    return zero_fcodual(y), NoPullback(kwcall, kwargs, f, args...)
end

end

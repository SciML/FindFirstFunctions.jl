# FindFirstFunctions

[![Build Status](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml?query=branch%3Amain)

FindFirstFunctions.jl is a package for faster `findfirst` type functions. These are specailized to improve performance
over more generic implementations.

## Functions

### `findfirstequal`

```julia
findfirstequal(x::Int64,A::DenseVector{Int64})
```

Finds the first value in `A` equal to `x`

### `bracketstrictlymontonic`

```julia
bracketstrictlymontonic(v, x, guess; lt=<comparison>, by=<transform>, rev=false)
```

Starting from an initial `guess` index, find indices `(lo, hi)` such that `v[lo] ≤ x ≤
v[hi]` according to the specified order, assuming that `x` is actually within the range of
values found in `v`.  If `x` is outside that range, either `lo` will be `firstindex(v)` or
`hi` will be `lastindex(v)`.

Note that the results will not typically satisfy `lo ≤ guess ≤ hi`.  If `x` is precisely
equal to a value that is not unique in the input `v`, there is no guarantee that `(lo, hi)`
will encompass *all* indices corresponding to that value.

This algorithm is essentially an expanding binary search, which can be used as a precursor
to `searchsorted` and related functions, which can take `lo` and `hi` as arguments.  The
purpose of using this function first would be to accelerate convergence in those functions
by using correlated `guess`es for repeated calls.  The best `guess` for the next call of
this function would be the index returned by the previous call to `searchsorted`.

See `sort!` for an explanation of the keyword arguments `by`, `lt` and `rev`.

### `searchsortedfirstcorrelated(v::AbstractVector, x, guess)`

```julia
searchsortedfirstcorrelated(v::AbstractVector{T}, x, guess::T)
```

An accelerated `findfirst` on sorted vectors using a bracketed search. Requires a `guess`
to start the search from.

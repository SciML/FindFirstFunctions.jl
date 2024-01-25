# FindFirstFunctions

[![Build Status](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml?query=branch%3Amain)

FindFirstFunctions.jl is a package for faster `findfirst` type functions. These are specailized to improve performance
over more generic implementations.

## Functions

* `findfirstequal(x::Int64,A::DenseVector{Int64})`: finds the first value in `A` equal to `x`

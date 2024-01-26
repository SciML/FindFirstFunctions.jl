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


Some benchmarks:
```julia
using Random
x = rand(Int, 2048); s = sort(x);
perm = randperm(length(x));

function findbench(f, x, vals)
    @inbounds for i = eachindex(x, vals)
        v = vals[i]
        f(x[v], x) == v || throw("oops")
    end
end

@benchmark findbench(FindFirstFunctions.findfirstequal, $x, $perm)
@benchmark findbench((x,v)->findfirst(==(x), v), $x, $perm)

@benchmark findbench(FindFirstFunctions.findfirstsortedequal, $s, $perm)
@benchmark findbench((x,v)->searchsortedfirst(v, x), $s, $perm)
```
Sample results using `-Cnative,-prefer-256-bit` on an AVX512 capable laptop:
```julia
julia> @benchmark findbench(FindFirstFunctions.findfirstequal, $x, $perm)
BenchmarkTools.Trial: 9219 samples with 1 evaluation.
 Range (min … max):  107.094 μs … 137.850 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     107.376 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   107.577 μs ±   1.175 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

     ▁▇█▆▁                                                       
  ▂▃▅█████▅▃▂▂▂▂▂▁▁▁▁▁▂▂▂▃▃▃▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▁▂▂▁▂▁▁▁▂▂▁▂ ▃
  107 μs           Histogram: frequency by time          110 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->findfirst(==(x), v), $x, $perm)
BenchmarkTools.Trial: 2144 samples with 1 evaluation.
 Range (min … max):  462.442 μs … 584.795 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     464.638 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   465.686 μs ±   5.534 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

       █ ▅▇▂                                                     
  ▅▃▁▁▁█▇███▇▆▃▆▃▁▄▃▄▁▃▃▁▁▁▁▃▁▄▁▁▃▁▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▃▃▃▃▃▄▃▁▁▁▃▄▃ █
  462 μs        Histogram: log(frequency) by time        486 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench(FindFirstFunctions.findfirstsortedequal, $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  46.256 μs … 88.446 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     48.048 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   48.702 μs ±  2.079 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

      ▂▅▇█▇▇▆▄▃▁                                               
  ▁▃▆▇███████████▇▇▆▅▅▅▄▄▃▃▃▂▃▂▃▂▂▂▂▂▂▂▂▂▂▂▁▁▂▂▂▂▁▂▁▂▁▂▁▁▂▁▂▂ ▃
  46.3 μs         Histogram: frequency by time          56 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->searchsortedfirst(v, x), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  77.387 μs … 108.634 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     79.305 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   81.398 μs ±   4.536 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

      ▃▆█▆▃                                                     
  ▁▃▅▇██████▅▄▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▂▄▄▃▃▂▃▃▃▂▂▁▁▁ ▂
  77.4 μs         Histogram: frequency by time         92.6 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> versioninfo()
Julia Version 1.10.0
Commit 3120989f39* (2023-12-25 18:01 UTC)
Build Info:

    Note: This is an unofficial build, please report bugs to the project
    responsible for this build and not to the Julia project unless you can
    reproduce the issue using official builds available at https://julialang.org/downloads

Platform Info:
  OS: Linux (x86_64-redhat-linux)
  CPU: 8 × 11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, tigerlake)
  Threads: 11 on 8 virtual cores
Environment:
  JULIA_PATH = @.
  LD_LIBRARY_PATH = /usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/:/usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/
  JULIA_NUM_THREADS = 8
  LD_UN_PATH = /usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/
```

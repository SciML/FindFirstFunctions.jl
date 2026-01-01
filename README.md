# FindFirstFunctions

[![Build Status](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/SciML/FindFirstFunctions.jl/actions/workflows/CI.yml?query=branch%3Amain)

FindFirstFunctions.jl is a package for faster `findfirst` type functions. These are specialized to improve performance
over more generic implementations.

## Functions

### `findfirstequal`

```julia
findfirstequal(x::Int64,A::DenseVector{Int64})
```

Finds the first index in `A` where the value equals `x`.

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

See `Base.sort!` for an explanation of the keyword arguments `by`, `lt` and `rev`.

### `searchsortedfirstcorrelated(v::AbstractVector, x, guess)`

```julia
searchsortedfirstcorrelated(v::AbstractVector, x, guess)
```

An accelerated `findfirst` on sorted vectors using a bracketed search. Requires a `guess`
to start the search from, which is either an integer or an instance of `Guesser`.

An analogous function `searchsortedlastcorrelated` exists.


Some benchmarks:
```julia
using Random, BenchmarkTools, FindFirstFunctions
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
BenchmarkTools.Trial: 6794 samples with 1 evaluation.
 Range (min … max):  141.489 μs … 190.383 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     145.892 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   145.978 μs ±   4.697 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▇▅     ▁▁  ▁█▅     ▁▂▁  ▂▃▂     ▁           ▁                 ▁
  ██▆▁▁▁▃██▆▄███▄▃▄▃▄███▁▆████▅▅▅▇█▇▇▆▆▆▆▇▆▅▃▇█▆▇▇▆▅▆▇▇▇▇▆▇█▅▅▅ █
  141 μs        Histogram: log(frequency) by time        163 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->findfirst(==(x), v), $x, $perm)
BenchmarkTools.Trial: 1765 samples with 1 evaluation.
 Range (min … max):  547.812 μs … 663.534 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     564.245 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   565.600 μs ±  14.561 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▇▄▄▄    ▄ █▄▅▆▅ ▂▁▂▅▃▃▅       ▁                               ▁
  ████▁▁▁▁█▇████████████████▇█▇██▆▅▆▅▅▄▅▅▄▄▆▁▄▄▅▅▅▁▁▅▅▅▅▆▄▁▁▁▄▅ █
  548 μs        Histogram: log(frequency) by time        628 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench(FindFirstFunctions.findfirstsortedequal, $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  75.857 μs … 125.111 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     85.811 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   86.135 μs ±   3.217 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

                    ▁   ▂██▃                                    
  ▂▁▁▁▂▂▁▁▁▁▁▁▁▂▂▃▅██▆▄▆████▅▄▃▃▃▃▃▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂ ▃
  75.9 μs         Histogram: frequency by time          101 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->searchsortedfirst(v, x), $s, $perm)
BenchmarkTools.Trial: 8741 samples with 1 evaluation.
 Range (min … max):  108.941 μs … 152.368 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     113.026 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   113.282 μs ±   3.812 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

     ▂▅▂     ▄█▇▂                                                
  ▁▂▅███▆▃▂▃▆████▆▂▂▂▂▂▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▂
  109 μs           Histogram: frequency by time          130 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> versioninfo()
Julia Version 1.10.0
Commit 3120989f39 (2023-12-25 18:01 UTC)
Build Info:

    Note: This is an unofficial build, please report bugs to the project
    responsible for this build and not to the Julia project unless you can
    reproduce the issue using official builds available at https://julialang.org/downloads

Platform Info:
  OS: Linux (x86_64-redhat-linux)
  CPU: 36 × Intel(R) Core(TM) i9-7980XE CPU @ 2.60GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, skylake-avx512)
  Threads: 1 on 36 virtual cores
Environment:
  JULIA_PATH = @.
  LD_LIBRARY_PATH = /usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/:/usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/
  JULIA_NUM_THREADS = 36
  LD_UN_PATH = /usr/local/lib/x86_64-unknown-linux-gnu/:/usr/local/lib/
```


Note, if you're searching sorted collections and on an x86 CPU, it is worth setting the `ENV` variable `JULIA_LLVM_ARGS="-x86-cmov-converter=false"` before starting Julia, e.g. on an AVX512 capable CPU, you may wish to start Julia from the command line using
```sh
JULIA_LLVM_ARGS="-x86-cmov-converter=false" julia -Cnative,-prefer-256-bit
```
With this, benchmark results are
```julia
julia> @benchmark findbench(FindFirstFunctions.findfirstequal, $x, $perm)
BenchmarkTools.Trial: 6623 samples with 1 evaluation.
 Range (min … max):  141.304 μs … 473.786 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     145.581 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   149.690 μs ±  28.577 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  █▇▃▄▃▂▁▁▁  ▂                                 ▁                ▁
  ██████████▆█▇▆▇▆▅▄▅▁▅▅▃▄▅▁▃▃▁▃▃▁▁▄▁▁▁▁▁▁▁▁▃▁▁█▄▆▅▅▁▁▃▁▁▁▃▁▁▁▃ █
  141 μs        Histogram: log(frequency) by time        302 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->findfirst(==(x), v), $x, $perm)
BenchmarkTools.Trial: 1784 samples with 1 evaluation.
 Range (min … max):  546.395 μs … 660.254 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     560.513 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   559.546 μs ±  14.138 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  █▆▄▇      ▆▇▄▄█▂▂▁▂▁▁▁▁                                       ▁
  ████▄▁▅▁▇▅█████████████▆▇▇▅▄▅▅▄▁▄▅▆▄▅▆▄▆▄▄▅▄▁▁▁▁▁▅▁▁▄▄▅▆▄▄▄▁▇ █
  546 μs        Histogram: log(frequency) by time        625 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench(FindFirstFunctions.findfirstsortedequal, $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  45.969 μs … 73.354 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     47.674 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   47.675 μs ±  1.999 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▃▇▇▅  ▁▆██▅   ▁▂▃▂   ▁▂▁                                    ▂
  █████▅██████▆▇████▇▄▇████▆▅▄▆████▇▆▆▁▁▁▁▄▄▃▃▃▃▁▁▁▁▁▁▃▄▆▅▆▄▆ █
  46 μs        Histogram: log(frequency) by time      58.1 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->searchsortedfirst(v, x), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  35.988 μs … 224.353 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     37.807 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   38.966 μs ±   7.905 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

   ▁▇▆▅█▅          ▃▂ ▁▂                                       ▂
  ▇██████▄▇█▆▆███▇███▇███▄▄▁▅▃▅▅▄▄▇██▆▇▇▃▅▄▅▄▆▇▅▄▄▆▇▇▅▄▅▅▁▃▁▄▄ █
  36 μs         Histogram: log(frequency) by time        57 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->FindFirstFunctions.findfirstsortedequal(x,v,Val(64)), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  43.709 μs … 182.914 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     45.227 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   45.954 μs ±   5.377 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▃▇█▅▂▆█▇▃▁▂▂▁  ▁▁▁▁  ▁ ▁                ▁▁                   ▂
  █████████████▆▇████▇████▇▇▆▆▇█▇▅▆▆▅▄▄▅▆███▇▆██▆▅▅▅▃▄▁▄▄▅▆▅▆▆ █
  43.7 μs       Histogram: log(frequency) by time      61.4 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->FindFirstFunctions.findfirstsortedequal(x,v,Val(32)), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  42.482 μs … 172.067 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     44.422 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   45.765 μs ±   8.329 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▆███▄▂ ▂▁▃▃                                                  ▂
  ████████████▆▆▆▅▆██▇▄▄▃▄▅▇▇▄▄▄▃▄▄▁▃▁▁▁▃▁▃▁▃▁▁▁▃██▇▇▄▁▃▄▁▄▄▄▃ █
  42.5 μs       Histogram: log(frequency) by time      83.3 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->FindFirstFunctions.findfirstsortedequal(x,v,Val(16)), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  36.870 μs … 154.299 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     39.764 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   40.400 μs ±   2.552 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

   ▁▂▁   ▂▆██▆▅▆▇▆▃▂▃▃▂    ▁▁                                  ▂
  ▆███▃▃▅███████████████▇▇████▇▆▆▇▇▇▇▆▆▆▅▃▃▅▅▅▅▄▆▆▅▅▇▇▅▆▅▅▃▁▃▅ █
  36.9 μs       Histogram: log(frequency) by time        53 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark findbench((x,v)->FindFirstFunctions.findfirstsortedequal(x,v,Val(8)), $s, $perm)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  26.011 μs … 48.109 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     26.954 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   27.046 μs ±  1.677 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▆▆  █▆  ▂                                                   ▂
  ██▁▇██▅▁█▆▁▁▆▇▅▅▅▆▇▇▆▅▆▆▆▅▆▇██▇▅▃▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▅▅▅▇▅▃▅ █
  26 μs        Histogram: log(frequency) by time      37.9 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.
```
The branches in a binary search are unpredictable, thus disabling the conversion of `cmov` into branches results in a substantial performance increase.
Additionally, enablig `cmov` (i.e., disabling `cmov` conversion) greatly reduces the optimal base case size for `FindFirstFunctions.findfirstsortedequal`. Without `cmov`, we need a very large base case to avoid too many branches, scanning large swaths contiguously.
With `cmov`, we can reduce the base case size to `8`, taking several additional binary search steps without incurring heavy branch prediction penalties.

However, we default to a large base case size, under the assumptions users are not setting this `ENV` variable; we assume that an expert user concerned about binary search performance who sets this variable will also be able to choose their own basecase size.

Take care when benchmarking `JULIA_LLVM_ARGS="-x86-cmov-converter=false"`: your CPU's branch predictor can probably memorize a sequence of hundreds of perfectly random branches. Branch predcitors are great at defeating microbenchmarks.
Thus, you need a very long unpredictable sequence (which I tried to do in the above benchmark) to prevent the branch predictor from memorizing it.
In "real world" workloads, your branch predictor isn't going to be able to memorize a sequence of left vs right bisections in your binary search, as you won't be performing the same searches over and over again!
Without making your benchmark realistic, the default setting of converting `cmov` into branches will look unrealistically good.

If you actually are, memoize. If you're looking for close answers, look for something like `bracketstrictlymontonic`'s `guess` API.

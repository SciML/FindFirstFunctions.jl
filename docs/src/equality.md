# Equality search

This page documents the package's equality-search routines —
[`findfirstequal`](@ref FindFirstFunctions.findfirstequal) and
[`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal). They
answer a *different* question from the [Search strategies](@ref) covered
elsewhere:

  - **Sorted-search** strategies answer "*where would `x` insert?*". The
    return value is always an in-range index — the bracketing position.
  - **Equality** search answers "*does `x` exist, and if so at what index?*".
    The return value is `nothing` if `x` is not present.

These two surfaces live side-by-side because the second cannot be expressed
as a `SearchStrategy` — its return type differs (`Union{Int, Nothing}` vs.
in-range `Int`), and the unsorted variant doesn't even require a sorted
input.

For a strategy-framework-compatible *sorted* equality search that returns
`Int` with a sentinel (so it composes with the rest of the strategy
dispatch), see [`findequal`](@ref FindFirstFunctions.findequal) on the
[Search strategies](@ref) page. `findequal(BisectThenSIMD(), v, x)` is the
strategy entry point that internally calls into the same algorithm as
`findfirstsortedequal`.

## API reference

```@docs
FindFirstFunctions.findfirstequal
FindFirstFunctions.findfirstsortedequal
```

## When to use which

| Question | Vector | Recommended |
|---|---|---|
| Does `x` occur in this *unsorted* vector? | any | [`findfirstequal`](@ref FindFirstFunctions.findfirstequal) |
| Does `x` occur in this *sorted* vector? | `DenseVector{Int64}` + `Int64` | [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal) (or `findequal(BisectThenSIMD(), v, x)` for the sentinel-returning variant) |
| Does `x` occur in this *sorted* vector? | other eltypes | [`findequal`](@ref FindFirstFunctions.findequal) with any strategy |
| Where would `x` insert into this sorted vector? | any | `searchsortedfirst(strategy, v, x[, hint])` |

## SIMD primitives

Both equality functions are backed by the same SIMD-equality LLVM IR
scaffolding used internally throughout the package (`load <8 x i64>`,
`icmp eq`, `cttz` on the bitmask of the 8-wide compare). The IR template
[`FindFirstFunctions._simd_scan_ir`](@ref) generates this for the equality
predicate; the same template generates the `>` / `>=` variants for
[`SIMDLinearScan`](@ref FindFirstFunctions.SIMDLinearScan).

The SIMD path is `Int64`-only — the LLVM IR is keyed off `i64` element
width and 8-byte stride. Every other element type and storage layout
falls through to a scalar `findfirst(==(x), v)` path. Specifically:

  - `findfirstequal(x::Int64, v::DenseVector{Int64})` — full SIMD scan.
  - `findfirstequal(x, v)` (generic) — `findfirst(isequal(x), v)`.
  - `findfirstsortedequal(x::Int64, v::DenseVector{Int64})` — branchless
    binary bisection to a small basecase, then SIMD equality scan within
    the basecase window. The bisection uses a strict `<` predicate so
    that earlier duplicates are not skipped (a previous version of the
    routine used `<=` and could return a later duplicate; fixed in 2.0).

## Sentinel vs. `Nothing`

The two equality APIs differ in how they report "not found":

```julia
findfirstequal(x, v)        # -> Union{Int, Nothing}, `nothing` on miss
findfirstsortedequal(x, v)  # -> Union{Int, Nothing}, `nothing` on miss
findequal(strategy, v, x)   # -> Int, firstindex(v) - 1 on miss
```

`findequal`'s sentinel is type-stable and composes with the rest of the
strategy dispatch — that's the recommended choice for new sorted-equality
code. The two `findfirst*equal` names continue to return
`Union{Int, Nothing}` for backwards compatibility with callers and pattern
matching against `nothing`.

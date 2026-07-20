# FindFirstFunctions.jl

FindFirstFunctions.jl is a library of accelerated `findfirst`-style and
sorted-search routines. The package provides:

  - A **strategy-dispatched** sorted-search API: a single pair of
    `Base.searchsortedfirst` / `Base.searchsortedlast` overloads that take a
    [`SearchStrategy`](@ref FindFirstFunctions.SearchStrategy) as the first
    positional argument.
  - **Batched** in-place lookups
    [`searchsortedfirst!`](@ref FindFirstFunctions.searchsortedfirst!) /
    [`searchsortedlast!`](@ref FindFirstFunctions.searchsortedlast!) that pick
    a strategy automatically.
  - **Guessers** that supply per-vector hints based on linear extrapolation
    or a cached previous result.
  - **Equality search** via [`findfirstequal`](@ref FindFirstFunctions.findfirstequal)
    and [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal).

## Installation

```julia
using Pkg
Pkg.add("FindFirstFunctions")
```

## Guide

  - [Interface and extension rules](@ref) — the public API surface, the
    contract a `SearchStrategy` subtype must satisfy, and how to add a new
    one.
  - [Search strategies](@ref) — catalog of the built-in strategies, when each
    one is fast, and when it falls back to plain binary search.
  - [Guessers](@ref) — the [`Guesser`](@ref FindFirstFunctions.Guesser) type
    and how to plug it into the strategy dispatch via
    [`GuesserHint`](@ref FindFirstFunctions.GuesserHint).
  - [Auto: heuristics and benchmarks](@ref) — what
    [`Auto`](@ref FindFirstFunctions.Auto) picks in every regime, the
    crossover constants, and the benchmark script that validates them.
  - [Equality search](@ref) — the dedicated equality routines
    [`findfirstequal`](@ref FindFirstFunctions.findfirstequal) and
    [`findfirstsortedequal`](@ref FindFirstFunctions.findfirstsortedequal),
    which live outside the strategy framework because their return type is
    `Union{Int, Nothing}`.

## Quick example

```julia
using FindFirstFunctions

v = collect(0.0:0.1:10.0)
queries = sort!(rand(100) .* 10)

# Single query with a hint.
i = searchsorted_last(BracketGallop(), v, 3.14, 30)

# Batched, with strategy chosen by Auto.
idx = Vector{Int}(undef, length(queries))
searchsortedlast!(idx, v, queries)
```

## Contributing

  - Please refer to the
    [SciML ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://sciml.github.io/ColPrac/stable/)
    for guidance on PRs, issues, and other matters relating to contributing to SciML.

  - See the [SciML Style Guide](https://github.com/SciML/SciMLStyle) for common coding practices and other style decisions.
  - There are a few community forums:
    
      + The #diffeq-bridged and #sciml-bridged channels in the
        [Julia Slack](https://julialang.org/slack/)
      + The #diffeq-bridged and #sciml-bridged channels in the
        [Julia Zulip](https://julialang.zulipchat.com/#narrow/stream/279055-sciml-bridged)
      + On the [Julia Discourse forums](https://discourse.julialang.org)
      + See also [SciML Community page](https://sciml.ai/community/)

## Reproducibility

```@raw html
<details><summary>The documentation of this SciML package was built using these direct dependencies,</summary>
```

```@example
using Pkg # hide
Pkg.status() # hide
```

```@raw html
</details>
```

```@raw html
<details><summary>and using this machine and Julia version.</summary>
```

```@example
using InteractiveUtils # hide
versioninfo() # hide
```

```@raw html
</details>
```

```@raw html
<details><summary>A more complete overview of all dependencies and their versions is also provided.</summary>
```

```@example
using Pkg # hide
Pkg.status(; mode = PKGMODE_MANIFEST) # hide
```

```@raw html
</details>
```

```@eval
using TOML
using Markdown
version = TOML.parse(read("../../Project.toml", String))["version"]
name = TOML.parse(read("../../Project.toml", String))["name"]
link_manifest = "https://github.com/SciML/" * name * ".jl/tree/gh-pages/v" * version *
                "/assets/Manifest.toml"
link_project = "https://github.com/SciML/" * name * ".jl/tree/gh-pages/v" * version *
               "/assets/Project.toml"
Markdown.parse("""You can also download the
[manifest]($link_manifest)
file and the
[project]($link_project)
file.
""")
```

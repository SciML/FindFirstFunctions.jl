# Guessers

A [`Guesser`](@ref FindFirstFunctions.Guesser) is a small wrapper around a
sorted vector that produces an integer index hint for a given query, using
one of two strategies decided at construction time:

  - **Linear-extrapolation lookup**, when `v` is approximately uniformly
    spaced. The guess is `firstindex(v) + round((x - v[1]) / (v[end] - v[1]) * (length(v) - 1))`.
    Cost is O(1) per call, independent of `length(v)`.
  - **Cached previous result**, otherwise. The guesser hands back its
    `idx_prev` field. Useful for callers that issue temporally-correlated
    queries — the previous answer is a good seed for `BracketGallop`.

The Guesser does **not** perform the actual search. To use it as a search
strategy, wrap it in [`GuesserHint`](@ref FindFirstFunctions.GuesserHint).

## Construction

```@docs
FindFirstFunctions.Guesser
```

The threshold passed via `looks_linear_threshold` is the same threshold used
by [`looks_linear`](@ref FindFirstFunctions.looks_linear) (which the Guesser
calls under the hood). The default `1e-2` accepts everything from exact
linear ranges through evenly-spaced grids with mild jitter, but rejects
log-spaced or piecewise-spaced data.

```@docs
FindFirstFunctions.looks_linear
```

## Calling a Guesser

`guesser(x)` returns an integer index hint, but does **not** update any
state. The returned hint may be outside `axes(v)` if `x` is past either end
of `v`; callers should treat the hint as advisory and clamp.

```julia
v = collect(0.0:0.1:10.0)
g = Guesser(v)
g(3.14)   # → 32, an O(1) extrapolation guess
```

For irregular data the same call returns `g.idx_prev[]` — the last index
written by a [`GuesserHint`](@ref FindFirstFunctions.GuesserHint) search (or
`1` if no search has run yet).

## Plugging into the strategy dispatch

[`GuesserHint`](@ref FindFirstFunctions.GuesserHint) is the strategy adapter
that turns a `Guesser` into a `SearchStrategy`. It:

  1. Calls `guesser(x)` to obtain an integer guess.
  2. Dispatches to [`BracketGallop`](@ref FindFirstFunctions.BracketGallop)
     from that guess.
  3. Writes the resulting index back into `guesser.idx_prev`.

```@docs
FindFirstFunctions.GuesserHint
```

Per-call cost is one `guesser(x)` evaluation (O(1)) plus one `BracketGallop`
(O(1) when the guess is close) plus one `idx_prev[]` write.

The vector passed to `searchsortedfirst` / `searchsortedlast` must be the
same object the Guesser wraps — `GuesserHint` asserts `v === s.guesser.v` to
catch the obvious misuse.

```julia
v = collect(0.0:0.1:10.0)
g = Guesser(v)
strat = GuesserHint(g)

i = search_last(strat, v, 3.14)
@assert g.idx_prev[] == i   # the guesser caches the last result
```

`GuesserHint` ignores any externally-supplied hint — the Guesser carries its
own hint state, and accepting a foreign hint would defeat the cache.

## Pattern: correlated lookups for interpolation

The intended use is a wrapper struct that owns both the sorted vector and a
matching `Guesser`. Every query against the wrapper feeds through
`GuesserHint`:

```julia
struct Interp{V}
    v::V
    g::Guesser{V}
end
Interp(v) = Interp(v, Guesser(v))

function find_segment(itp::Interp, x)
    return search_last(GuesserHint(itp.g), itp.v, x)
end
```

After warmup, repeated calls to `find_segment` with temporally correlated
`x` cost O(1): the previous result is one slot away from the current
answer, so the `BracketGallop` inside `GuesserHint` returns after a couple
of comparisons.

## When not to use a Guesser

  - **One-shot queries.** Construct cost is O(n) for the `looks_linear`
    probe — wasted if you only intend to search once. Use
    [`BinaryBracket`](@ref FindFirstFunctions.BinaryBracket) or pass `Auto()`
    with no hint.
  - **Sorted batches.** The batched
    [`searchsortedlast!`](@ref FindFirstFunctions.searchsortedlast!) /
    [`searchsortedfirst!`](@ref FindFirstFunctions.searchsortedfirst!) APIs
    already do `prev_result`-style hinting internally; they don't need a
    Guesser and they pick a faster strategy when the sweep is dense.
  - **Strictly random queries against irregular `v`.** `looks_linear` returns
    false, so the Guesser degrades to returning `idx_prev[]`, which is
    useless for random queries. `BracketGallop` from `idx_prev` is fine but
    `Auto`-on-a-batch does the same thing without the Guesser overhead.

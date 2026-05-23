#=
Per-query latency: UniformStep via Auto+props (closed-form, precomputed
inv_step) vs UniformStep via raw struct (fld(diff, step) per query) vs
BracketGallop with valid hint.

Usage:
    julia +1.11 --project=bench bench/uniform_step_props_bench.jl
=#

import Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Statistics
using StableRNGs

using FindFirstFunctions
using FindFirstFunctions: Auto, UniformStep, BracketGallop, SearchProperties

const RNG = StableRNG(12345)

function bench_per_query(strategy_or_kind, v, queries)
    out = Vector{Int}(undef, length(queries))
    bench = @benchmarkable for k in eachindex($queries)
        $out[k] = $(
            strategy_or_kind isa FindFirstFunctions.SearchStrategy ?
                :(searchsortedlast) : :(FindFirstFunctions.search_last)
        )($strategy_or_kind, $v, $queries[k])
    end seconds = 1 evals = 1 samples = 200
    return run(bench)
end

# Two-arg form (per-query, no hint), Auto-style:
function bench_auto(s, v, queries)
    out = Vector{Int}(undef, length(queries))
    bench = @benchmarkable for k in eachindex($queries)
        $out[k] = searchsortedlast($s, $v, $queries[k])
    end seconds = 1 evals = 1 samples = 200
    return run(bench)
end

# BracketGallop with chained hint (monotone queries).
function bench_bracket_hint(s, v, queries)
    out = Vector{Int}(undef, length(queries))
    bench = @benchmarkable begin
        h = firstindex($v) - 1
        for k in eachindex($queries)
            h = if h < firstindex($v)
                searchsortedlast($s, $v, $queries[k])
            else
                searchsortedlast($s, $v, $queries[k], h)
            end
            $out[k] = h
        end
    end seconds = 1 evals = 1 samples = 200
    return run(bench)
end

fmt(t) = string(round(median(t).time / length(QUERIES); digits = 2), " ns/q")

const N = 10_000
const M = 1_000

const r = range(0.0, 100.0; length = N)
const v_uniform = collect(r)
const queries_sorted = sort!(rand(RNG, M) .* 100.0)
const queries_random = rand(StableRNG(11), M) .* 100.0
const QUERIES = queries_sorted

println("==== n = $N, m = $M ====\n")

println("=== Sorted queries on AbstractRange (range) ===")
println("Auto(r) (UniformStep + props)        : ", fmt(bench_auto(Auto(r), r, queries_sorted)))
println("UniformStep() (range path, fld)      : ", fmt(bench_auto(UniformStep(), r, queries_sorted)))
println("BracketGallop() (with hint chain)    : ", fmt(bench_bracket_hint(BracketGallop(), r, queries_sorted)))

println("\n=== Sorted queries on Vector{Float64} (uniform) ===")
println("Auto(v) (UniformStep + props)        : ", fmt(bench_auto(Auto(v_uniform), v_uniform, queries_sorted)))
println("UniformStep() (vector path → bracket): ", fmt(bench_auto(UniformStep(), v_uniform, queries_sorted)))
println("BracketGallop() (with hint chain)    : ", fmt(bench_bracket_hint(BracketGallop(), v_uniform, queries_sorted)))

println("\n=== Random queries on AbstractRange ===")
println("Auto(r) (UniformStep + props)        : ", fmt(bench_auto(Auto(r), r, queries_random)))
println("UniformStep() (range path, fld)      : ", fmt(bench_auto(UniformStep(), r, queries_random)))
println("BracketGallop() (hinted, miss path)  : ", fmt(bench_bracket_hint(BracketGallop(), r, queries_random)))

println("\n=== Random queries on Vector{Float64} (uniform) ===")
println("Auto(v) (UniformStep + props)        : ", fmt(bench_auto(Auto(v_uniform), v_uniform, queries_random)))
println("BracketGallop() (hinted, miss path)  : ", fmt(bench_bracket_hint(BracketGallop(), v_uniform, queries_random)))

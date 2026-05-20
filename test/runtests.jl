using Pkg
using SafeTestsets, Test

const GROUP = get(ENV, "GROUP", "All")

function activate_qa_env()
    Pkg.activate("qa")
    Pkg.develop(PackageSpec(path = dirname(@__DIR__)))
    return Pkg.instantiate()
end

@testset "FindFirstFunctions" begin
    if GROUP == "All" || GROUP == "Core"
        @safetestset "FindFirstFunctions.jl" begin
            using FindFirstFunctions
            for n in 0:128
                x = unique!(rand(Int, n))
                s = sort(x)
                for i in eachindex(x)
                    @test FindFirstFunctions.findfirstequal(x[i], x) == i
                    @test FindFirstFunctions.findfirstequal(s[i], s) == i
                    @test FindFirstFunctions.findfirstsortedequal(s[i], s) == i
                end
                if length(x) > 0
                    @test FindFirstFunctions.findfirstequal(x[begin], @view(x[begin:end])) === 1
                    @test FindFirstFunctions.findfirstequal(x[begin], @view(x[(begin + 1):end])) ===
                        nothing
                    @test FindFirstFunctions.findfirstequal(x[end], @view(x[begin:(end - 1)])) ===
                        nothing
                end
                y = rand(Int)
                ff = findfirst(==(y), x)
                @test FindFirstFunctions.findfirstequal(y, x) === ff
                ff === nothing &&
                    @test FindFirstFunctions.findfirstsortedequal(y, x) === nothing
            end
        end

        @safetestset "Guesser" begin
            using FindFirstFunctions: Guesser, GuesserHint
            v = collect(LinRange(0, 10, 4))
            guesser_linear = Guesser(v)
            guesser_prev = Guesser(v, Ref(1), false)
            @test guesser_linear.linear_lookup

            # Guesser feeds the dispatched API via GuesserHint.
            @test searchsortedfirst(GuesserHint(guesser_linear), v, 4.0) == 3
            @test searchsortedfirst(GuesserHint(guesser_linear), v, 1.4234326478e24) == 5
            @test searchsortedlast(GuesserHint(guesser_prev), v, 4.0) == 2
            @test guesser_prev.idx_prev[] == 2

            # Edge case: single-element v.
            v1 = [42.0]
            guesser = Guesser(v1)
            @test guesser_linear.linear_lookup
            @test guesser(100) == 1
            @test guesser(42.0) == 1
            @test guesser(0) == 1
            @test searchsortedfirst(GuesserHint(guesser), v1, 0) == 1
            @test searchsortedfirst(GuesserHint(guesser), v1, 100) == 2  # see Base.searchsortedfirst
            @test searchsortedfirst(GuesserHint(guesser), v1, 42.0) == 1
            @test searchsortedlast(GuesserHint(guesser), v1, 0) == 0  # see Base.searchsortedlast
            @test searchsortedlast(GuesserHint(guesser), v1, 100) == 1
            @test searchsortedlast(GuesserHint(guesser), v1, 42.0) == 1
        end

        @safetestset "Native reverse-order paths (issue #67)" begin
            using FindFirstFunctions, StableRNGs

            # ExpFromLeft, InterpolationSearch, SIMDLinearScan, and
            # BitInterpolationSearch all used to fall back to BinaryBracket
            # for `Base.Order.Reverse`. They now have native Reverse paths;
            # verify parity vs `Base.searchsorted*(v, x, Reverse)` across
            # eltypes and hint positions.

            rng = StableRNG(2027)
            order = Base.Order.Reverse

            @testset "Float64 reverse-sorted parity, m=200" begin
                # Decreasing sorted Float64 vector.
                v = sort!(randn(rng, 200); rev = true)
                for _ in 1:500
                    x = (rand(rng) - 0.5) * 6
                    hint = rand(rng, 1:length(v))
                    expected_last = searchsortedlast(v, x, order)
                    expected_first = searchsortedfirst(v, x, order)
                    for strategy in (
                            BinaryBracket(), LinearScan(), SIMDLinearScan(),
                            BracketGallop(), ExpFromLeft(),
                            InterpolationSearch(), BitInterpolationSearch(),
                            Auto(),
                        )
                        @test searchsortedlast(strategy, v, x, hint; order = order) ==
                            expected_last
                        @test searchsortedfirst(strategy, v, x, hint; order = order) ==
                            expected_first
                    end
                end
            end

            @testset "Int64 reverse-sorted parity, m=200" begin
                v = sort!(rand(rng, Int64(-100):Int64(100), 200); rev = true)
                for _ in 1:500
                    x = rand(rng, Int64(-110):Int64(110))
                    hint = rand(rng, 1:length(v))
                    expected_last = searchsortedlast(v, x, order)
                    expected_first = searchsortedfirst(v, x, order)
                    for strategy in (
                            BinaryBracket(), LinearScan(), SIMDLinearScan(),
                            BracketGallop(), ExpFromLeft(),
                            InterpolationSearch(), Auto(),
                        )
                        @test searchsortedlast(strategy, v, x, hint; order = order) ==
                            expected_last
                        @test searchsortedfirst(strategy, v, x, hint; order = order) ==
                            expected_first
                    end
                end
            end

            @testset "BitInterp reverse-sorted positive Float64" begin
                # Reverse log-spaced — exercises the bit-pattern Reverse path.
                v = sort!(collect(exp.(range(0.0, log(1.0e6); length = 1024))); rev = true)
                for _ in 1:200
                    x = exp(rand(rng) * log(1.0e6))
                    expected_last = searchsortedlast(v, x, order)
                    expected_first = searchsortedfirst(v, x, order)
                    @test searchsortedlast(
                        BitInterpolationSearch(), v, x; order = order
                    ) == expected_last
                    @test searchsortedfirst(
                        BitInterpolationSearch(), v, x; order = order
                    ) == expected_first
                end
                # Non-positive endpoint falls back to BinaryBracket cleanly.
                v_signed = sort!(randn(rng, 100); rev = true)
                for x in (-0.5, 0.0, 0.5, -2.0, 2.0)
                    @test searchsortedlast(
                        BitInterpolationSearch(), v_signed, x; order = order
                    ) == searchsortedlast(v_signed, x, order)
                end
            end

            @testset "Edge cases under Reverse" begin
                # Out-of-range queries: x larger than first, smaller than last.
                v = collect(10.0:-0.5:1.0)
                # x > v[1] → searchsortedfirst returns 1, searchsortedlast returns 0.
                for strategy in (
                        SIMDLinearScan(), ExpFromLeft(),
                        InterpolationSearch(), BitInterpolationSearch(),
                    )
                    @test searchsortedlast(strategy, v, 100.0, 5; order = order) ==
                        searchsortedlast(v, 100.0, order)
                    @test searchsortedlast(strategy, v, -100.0, 5; order = order) ==
                        searchsortedlast(v, -100.0, order)
                    @test searchsortedfirst(strategy, v, 100.0, 5; order = order) ==
                        searchsortedfirst(v, 100.0, order)
                    @test searchsortedfirst(strategy, v, -100.0, 5; order = order) ==
                        searchsortedfirst(v, -100.0, order)
                end
            end
        end

        @safetestset "Custom ordering for strategy dispatch" begin
            using FindFirstFunctions:
                Guesser, GuesserHint, BracketGallop, LinearScan,
                ExpFromLeft, BinaryBracket, Auto

            v_rev = collect(10.0:-1.0:1.0)
            for x in (5.0, 10.0, 1.0, 0.0, 11.0),
                    hint in (1, 5, 10),
                    strategy in (
                        BracketGallop(), LinearScan(), ExpFromLeft(), Auto(),
                    )

                @test searchsortedfirst(strategy, v_rev, x, hint; order = Base.Order.Reverse) ==
                    searchsortedfirst(v_rev, x, Base.Order.Reverse)
                @test searchsortedlast(strategy, v_rev, x, hint; order = Base.Order.Reverse) ==
                    searchsortedlast(v_rev, x, Base.Order.Reverse)
            end
            # BinaryBracket ignores any hint.
            for x in (5.0, 10.0, 1.0, 0.0, 11.0)
                @test searchsortedfirst(BinaryBracket(), v_rev, x; order = Base.Order.Reverse) ==
                    searchsortedfirst(v_rev, x, Base.Order.Reverse)
                @test searchsortedlast(BinaryBracket(), v_rev, x; order = Base.Order.Reverse) ==
                    searchsortedlast(v_rev, x, Base.Order.Reverse)
            end

            # GuesserHint with reverse order.
            guesser_rev = Guesser(v_rev)
            @test searchsortedfirst(GuesserHint(guesser_rev), v_rev, 5.0; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 5.0, Base.Order.Reverse)
            @test searchsortedlast(GuesserHint(guesser_rev), v_rev, 5.0; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 5.0, Base.Order.Reverse)

            # Default (Forward) order still resolves correctly.
            v_fwd = collect(1.0:1.0:10.0)
            for strategy in (BracketGallop(), LinearScan(), ExpFromLeft(), Auto())
                @test searchsortedfirst(strategy, v_fwd, 5.0, 1) == searchsortedfirst(v_fwd, 5.0)
                @test searchsortedlast(strategy, v_fwd, 5.0, 1) == searchsortedlast(v_fwd, 5.0)
            end
        end

        @safetestset "SearchStrategy dispatch (single query)" begin
            using FindFirstFunctions:
                SearchStrategy, LinearScan, BracketGallop, BinaryBracket, Auto

            for n in (0, 1, 2, 8, 33, 257)
                v = collect(1:n)
                isempty(v) && continue

                # Probe targets that include hits, misses, boundaries
                xs = unique!(sort!([0, 1, n ÷ 2, n, n + 1, -3, 2 * n + 1]))
                for x in xs
                    expected_last = searchsortedlast(v, x)
                    expected_first = searchsortedfirst(v, x)

                    # BinaryBracket — ignores any hint
                    @test searchsortedlast(BinaryBracket(), v, x) == expected_last
                    @test searchsortedfirst(BinaryBracket(), v, x) == expected_first
                    @test searchsortedlast(BinaryBracket(), v, x, 1) == expected_last
                    @test searchsortedfirst(BinaryBracket(), v, x, 1) == expected_first

                    # Strategy with hint anywhere in 1..n agrees with Base
                    for h in unique!([1, max(1, n ÷ 4), n ÷ 2, max(1, 3n ÷ 4), n])
                        @test searchsortedlast(LinearScan(), v, x, h) == expected_last
                        @test searchsortedfirst(LinearScan(), v, x, h) == expected_first
                        @test searchsortedlast(BracketGallop(), v, x, h) == expected_last
                        @test searchsortedfirst(BracketGallop(), v, x, h) == expected_first
                        @test searchsortedlast(Auto(), v, x, h) == expected_last
                        @test searchsortedfirst(Auto(), v, x, h) == expected_first
                    end

                    # No-hint forms fall back to BinaryBracket
                    @test searchsortedlast(LinearScan(), v, x) == expected_last
                    @test searchsortedfirst(LinearScan(), v, x) == expected_first
                    @test searchsortedlast(BracketGallop(), v, x) == expected_last
                    @test searchsortedfirst(BracketGallop(), v, x) == expected_first
                    @test searchsortedlast(Auto(), v, x) == expected_last
                    @test searchsortedfirst(Auto(), v, x) == expected_first

                    # Out-of-range hint → Auto falls back to BinaryBracket
                    @test searchsortedlast(Auto(), v, x, 0) == expected_last
                    @test searchsortedfirst(Auto(), v, x, 0) == expected_first
                    @test searchsortedlast(Auto(), v, x, n + 1) == expected_last
                    @test searchsortedfirst(Auto(), v, x, n + 1) == expected_first
                end
            end

            # Reverse order
            v_rev = collect(10.0:-1.0:1.0)
            for x in (0.5, 1.0, 5.0, 10.0, 11.0), h in (1, 5, 10)
                @test searchsortedlast(BracketGallop(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedlast(v_rev, x, Base.Order.Reverse)
                @test searchsortedfirst(BracketGallop(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedfirst(v_rev, x, Base.Order.Reverse)
                @test searchsortedlast(LinearScan(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedlast(v_rev, x, Base.Order.Reverse)
                @test searchsortedfirst(LinearScan(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedfirst(v_rev, x, Base.Order.Reverse)
                @test searchsortedlast(Auto(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedlast(v_rev, x, Base.Order.Reverse)
                @test searchsortedfirst(Auto(), v_rev, x, h; order = Base.Order.Reverse) ==
                    searchsortedfirst(v_rev, x, Base.Order.Reverse)
            end

            # Strategy abstract type hierarchy
            @test LinearScan <: SearchStrategy
            @test BracketGallop <: SearchStrategy
            @test BinaryBracket <: SearchStrategy
            @test Auto <: SearchStrategy
        end

        @safetestset "ExpFromLeft and InterpolationSearch" begin
            using FindFirstFunctions:
                ExpFromLeft, InterpolationSearch, BinaryBracket

            # ExpFromLeft on uniform Int range
            v = collect(1:1000)
            for x in (0, 1, 50, 250, 500, 999, 1000, 1001), h in (1, 50, 500, 1000)
                @test searchsortedlast(ExpFromLeft(), v, x, h) ==
                    searchsortedlast(v, x)
                @test searchsortedfirst(ExpFromLeft(), v, x, h) ==
                    searchsortedfirst(v, x)
            end
            # ExpFromLeft without hint falls back to BinaryBracket
            @test searchsortedlast(ExpFromLeft(), v, 500) == searchsortedlast(v, 500)
            @test searchsortedfirst(ExpFromLeft(), v, 500) == searchsortedfirst(v, 500)

            # InterpolationSearch on uniform Float64 range
            vf = collect(0.0:0.1:10.0)
            for x in (-1.0, 0.0, 0.05, 1.0, 5.5, 9.95, 10.0, 11.0)
                @test searchsortedlast(InterpolationSearch(), vf, x) ==
                    searchsortedlast(vf, x)
                @test searchsortedfirst(InterpolationSearch(), vf, x) ==
                    searchsortedfirst(vf, x)
            end

            # InterpolationSearch on log-spaced (non-uniform) — must still be correct
            vlog = exp.(range(log(0.1), log(100.0); length = 256))
            for x in (0.05, 0.1, 1.0, 50.0, 100.0, 150.0)
                @test searchsortedlast(InterpolationSearch(), vlog, x) ==
                    searchsortedlast(vlog, x)
                @test searchsortedfirst(InterpolationSearch(), vlog, x) ==
                    searchsortedfirst(vlog, x)
            end

            # InterpolationSearch ignores hint (computes its own guess)
            for h in (1, 100, 256)
                @test searchsortedlast(InterpolationSearch(), vlog, 50.0, h) ==
                    searchsortedlast(vlog, 50.0)
            end

            # InterpolationSearch falls back to BinaryBracket on non-Number eltypes
            vs = ["a", "b", "c", "d"]
            @test searchsortedlast(InterpolationSearch(), vs, "c") ==
                searchsortedlast(vs, "c")
            @test searchsortedfirst(InterpolationSearch(), vs, "c", 2) ==
                searchsortedfirst(vs, "c")

            # InterpolationSearch on a constant vector (span=0) shouldn't divide
            # by zero; should fall through to a bounded search and return a
            # correct result.
            vc = fill(3.0, 16)
            @test searchsortedlast(InterpolationSearch(), vc, 3.0) ==
                searchsortedlast(vc, 3.0)
            @test searchsortedlast(InterpolationSearch(), vc, 2.0) ==
                searchsortedlast(vc, 2.0)
            @test searchsortedlast(InterpolationSearch(), vc, 4.0) ==
                searchsortedlast(vc, 4.0)

            # Edge: 1-element and 2-element vectors
            @test searchsortedlast(ExpFromLeft(), [5], 4, 1) == 0
            @test searchsortedlast(ExpFromLeft(), [5], 5, 1) == 1
            @test searchsortedlast(ExpFromLeft(), [5], 6, 1) == 1
            @test searchsortedfirst(ExpFromLeft(), [5, 10], 7, 1) == 2
            @test searchsortedlast(InterpolationSearch(), [5], 4) == 0
            @test searchsortedlast(InterpolationSearch(), [5, 10], 7) == 1
        end

        @safetestset "Batched Auto heuristic" begin
            using FindFirstFunctions:
                Auto, LinearScan, ExpFromLeft, BracketGallop, BinaryBracket,
                searchsortedlast!
            using StableRNGs

            # Dense queries: Auto's avg-gap heuristic should land on LinearScan
            # (verified by output correctness, not by introspecting the picked
            # strategy — that's an implementation detail).
            v = collect(0.0:0.01:10.0)   # n=1001
            tt_dense = sort!(rand(StableRNG(1), 4096) .* 10.0)
            out_auto = Vector{Int}(undef, length(tt_dense))
            out_linear = Vector{Int}(undef, length(tt_dense))
            searchsortedlast!(out_auto, v, tt_dense; strategy = Auto())
            searchsortedlast!(out_linear, v, tt_dense; strategy = LinearScan())
            @test out_auto == out_linear

            # Sparse queries on a long vector: same correctness check.
            v_long = collect(0.0:0.001:100.0)  # n=100001
            tt_sparse = sort!(rand(StableRNG(2), 10) .* 100.0)
            out_a = Vector{Int}(undef, length(tt_sparse))
            out_e = Vector{Int}(undef, length(tt_sparse))
            searchsortedlast!(out_a, v_long, tt_sparse; strategy = Auto())
            searchsortedlast!(out_e, v_long, tt_sparse; strategy = ExpFromLeft())
            @test out_a == out_e

            # Dense burst — queries clustered inside one segment of v.
            # The span-based gap detection should send Auto to LinearScan.
            seg_lo = v[length(v) ÷ 2]
            seg_hi = v[length(v) ÷ 2 + 1]
            tt_burst = sort!(seg_lo .+ (seg_hi - seg_lo) .* rand(StableRNG(3), 2048))
            out_b = Vector{Int}(undef, length(tt_burst))
            out_l = Vector{Int}(undef, length(tt_burst))
            searchsortedlast!(out_b, v, tt_burst; strategy = Auto())
            searchsortedlast!(out_l, v, tt_burst; strategy = LinearScan())
            @test out_b == out_l

            # m=1 fast path — bypass span heuristic
            out1 = Vector{Int}(undef, 1)
            searchsortedlast!(out1, v, [5.123]; strategy = Auto())
            @test out1[1] == searchsortedlast(v, 5.123)

            # m=0 returns the output untouched (empty vector)
            empty_out = Int[]
            @test searchsortedlast!(empty_out, v, Float64[]; strategy = Auto()) === empty_out
            @test isempty(empty_out)

            # Non-numeric eltype: span heuristic falls back to length-ratio.
            vs = ["a", "b", "c", "d", "e", "f", "g", "h"]
            qs = ["b", "d", "f"]
            outs = Vector{Int}(undef, length(qs))
            searchsortedlast!(outs, vs, qs; strategy = Auto())
            @test outs == searchsortedlast.(Ref(vs), qs)
        end

        @safetestset "SearchProperties cache" begin
            using FindFirstFunctions:
                Auto, SearchProperties, searchsortedlast!, searchsortedfirst!
            using StableRNGs

            # The sentinel struct.
            @test !SearchProperties().has_props

            # A populated SearchProperties from a linear, NaN-free vector.
            v = collect(0.0:0.001:100.0)
            props = SearchProperties(v)
            @test props.has_props
            @test props.is_linear
            @test !props.has_nan

            # Output equivalence: Auto(props) returns the same answers as Auto()
            # on a sparse-on-long-linear regime (where InterpolationSearch is
            # the picked strategy via the cached `is_linear`).
            tt = sort!(rand(StableRNG(10), 16) .* 100.0)
            out_cached = Vector{Int}(undef, length(tt))
            out_baseline = Vector{Int}(undef, length(tt))
            out_truth = searchsortedlast.(Ref(v), tt)
            searchsortedlast!(out_cached, v, tt; strategy = Auto(props))
            searchsortedlast!(out_baseline, v, tt; strategy = Auto())
            @test out_cached == out_truth
            @test out_baseline == out_truth

            # searchsortedfirst path takes the same branch.
            searchsortedfirst!(out_cached, v, tt; strategy = Auto(props))
            searchsortedfirst!(out_baseline, v, tt; strategy = Auto())
            @test out_cached == searchsortedfirst.(Ref(v), tt)
            @test out_baseline == searchsortedfirst.(Ref(v), tt)

            # Float vector with a NaN: props.has_nan is true. The cache
            # currently isn't consumed for has_nan in Auto's decision tree,
            # but the field is populated correctly.
            vnan = [1.0, 2.0, NaN, 4.0, 5.0]
            propsnan = SearchProperties(vnan)
            @test propsnan.has_nan

            # Non-float eltype: has_nan is always false.
            vi = collect(Int64, 1:100)
            @test !SearchProperties(vi).has_nan

            # Lying SearchProperties (claims is_linear=true on non-linear data)
            # is still correctness-preserving — Auto's "InterpolationSearch on
            # linear data" branch handles the false positive gracefully
            # because InterpolationSearch's bad guess just makes BracketGallop
            # wider, never incorrect.
            v_log = exp.(range(0.0, 10.0; length = 4096))
            lying = SearchProperties(true, true, false, false)
            tt_log = sort!(rand(StableRNG(11), 8) .* (v_log[end] - v_log[1]) .+ v_log[1])
            out_lying = Vector{Int}(undef, length(tt_log))
            searchsortedlast!(out_lying, v_log, tt_log; strategy = Auto(lying))
            @test out_lying == searchsortedlast.(Ref(v_log), tt_log)

            # Bits-ness: SearchProperties must be isbits so it doesn't allocate.
            @test isbitstype(SearchProperties)

            # is_log_linear field: populated by SearchProperties(v) on
            # geometric data, rejected on linear / two-scale data.
            v_log = collect(exp.(range(0.0, log(1.0e6); length = 65536)))
            p_log = SearchProperties(v_log)
            @test p_log.is_log_linear

            v_lin = collect(0.0:0.001:65.0)
            p_lin = SearchProperties(v_lin)
            @test !p_lin.is_log_linear

            # Two-scale data should fail both linearity probes.
            v_2s = sort!(vcat(range(0.0, 1.0; length = 32768), range(1.0, 100.0; length = 32768)))
            p_2s = SearchProperties(v_2s)
            @test !p_2s.is_log_linear

            # is_log_linear requires strictly positive v; mixed-sign rejects.
            v_signed = collect(-100.0:0.001:65.0)
            p_signed = SearchProperties(v_signed)
            @test !p_signed.is_log_linear
        end

        @safetestset "Batched in-place searchsorted!" begin
            using FindFirstFunctions:
                LinearScan, BracketGallop, BinaryBracket, Auto,
                searchsortedlast!, searchsortedfirst!

            # Sorted queries
            v = collect(1:100)
            x_sorted = [5, 10, 20, 50, 90]
            out_last = Vector{Int}(undef, length(x_sorted))
            out_first = Vector{Int}(undef, length(x_sorted))

            @test searchsortedlast!(out_last, v, x_sorted) ==
                searchsortedlast.(Ref(v), x_sorted)
            @test searchsortedfirst!(out_first, v, x_sorted) ==
                searchsortedfirst.(Ref(v), x_sorted)
            @test out_last === searchsortedlast!(out_last, v, x_sorted)  # in-place

            # Each strategy gives the same result on sorted input
            for strategy in
                (LinearScan(), BracketGallop(), BinaryBracket(), Auto())
                fill!(out_last, 0)
                fill!(out_first, 0)
                searchsortedlast!(out_last, v, x_sorted; strategy = strategy)
                searchsortedfirst!(out_first, v, x_sorted; strategy = strategy)
                @test out_last == searchsortedlast.(Ref(v), x_sorted)
                @test out_first == searchsortedfirst.(Ref(v), x_sorted)
            end

            # Unsorted falls back to per-element regardless of strategy
            x_unsorted = [50, 10, 90, 5, 20]
            out = Vector{Int}(undef, length(x_unsorted))
            for strategy in (LinearScan(), BracketGallop(), Auto())
                searchsortedlast!(out, v, x_unsorted; strategy = strategy)
                @test out == searchsortedlast.(Ref(v), x_unsorted)
                searchsortedfirst!(out, v, x_unsorted; strategy = strategy)
                @test out == searchsortedfirst.(Ref(v), x_unsorted)
            end

            # Reverse-order vector + reverse-sorted queries
            v_rev = collect(10.0:-1.0:1.0)
            x_rev_sorted = [9.5, 7.5, 5.0, 2.5, 0.5]   # sorted descending
            out_r = Vector{Int}(undef, length(x_rev_sorted))
            searchsortedlast!(
                out_r, v_rev, x_rev_sorted; order = Base.Order.Reverse
            )
            @test out_r ==
                [searchsortedlast(v_rev, x, Base.Order.Reverse) for x in x_rev_sorted]

            # Floats + values between grid points
            vf = collect(0.0:0.1:10.0)
            xf = [0.5, 1.0, 2.5, 5.0, 9.5]
            outf = Vector{Int}(undef, length(xf))
            searchsortedlast!(outf, vf, xf)
            @test outf == searchsortedlast.(Ref(vf), xf)

            # Edge cases: out-of-range queries on each side
            x_edges = [-5.0, 0.0, 5.0, 10.0, 15.0]
            sort!(x_edges)
            oute = Vector{Int}(undef, length(x_edges))
            searchsortedlast!(oute, vf, x_edges)
            @test oute == searchsortedlast.(Ref(vf), x_edges)
            searchsortedfirst!(oute, vf, x_edges)
            @test oute == searchsortedfirst.(Ref(vf), x_edges)

            # Empty queries
            @test searchsortedlast!(Int[], v, Int[]) == Int[]
            @test searchsortedfirst!(Int[], v, Int[]) == Int[]

            # DimensionMismatch
            @test_throws DimensionMismatch searchsortedlast!(zeros(Int, 2), v, [1, 2, 3])
            @test_throws DimensionMismatch searchsortedfirst!(zeros(Int, 2), v, [1, 2, 3])

            # Sparse queries on a long vector — exercises the BracketGallop hint path
            v_big = collect(1:100_000)
            x_sparse = [100, 50_000, 99_900]
            outb = Vector{Int}(undef, length(x_sparse))
            searchsortedlast!(outb, v_big, x_sparse)
            @test outb == searchsortedlast.(Ref(v_big), x_sparse)

            # Range fast paths route through the strategy dispatch.
            r = 1:100
            outr = Vector{Int}(undef, length(x_sorted))
            for strategy in (LinearScan(), BracketGallop(), Auto())
                searchsortedlast!(outr, r, x_sorted; strategy = strategy)
                @test outr == searchsortedlast.(Ref(r), x_sorted)
            end
        end

        @safetestset "searchsortedrange" begin
            using FindFirstFunctions, StableRNGs
            v = collect(0.0:0.5:50.0)
            # Compare against Base composition for several (lo, hi) pairs.
            for (lo, hi) in [
                    (5.0, 7.0), (0.0, 100.0), (-1.0, 5.5), (10.0, 10.0),
                    (45.0, 60.0), (51.0, 100.0),
                ]
                expected = searchsortedfirst(v, lo):searchsortedlast(v, hi)
                for strategy in (
                        Auto(), BinaryBracket(), BracketGallop(), LinearScan(),
                        InterpolationSearch(), ExpFromLeft(), SIMDLinearScan(),
                    )
                    @test searchsortedrange(strategy, v, lo, hi) == expected
                    # Hinted form.
                    h = clamp(searchsortedfirst(v, lo), 1, length(v))
                    @test searchsortedrange(strategy, v, lo, hi, h) == expected
                end
            end
            # Random fuzz on Int64.
            rng = StableRNG(2026)
            vi = sort!(rand(rng, Int64(-100):Int64(100), 200))
            for _ in 1:200
                lo, hi = sort([rand(rng, Int64(-110):Int64(110)) for _ in 1:2])
                want = searchsortedfirst(vi, lo):searchsortedlast(vi, hi)
                @test searchsortedrange(Auto(), vi, lo, hi) == want
                @test searchsortedrange(BracketGallop(), vi, lo, hi, 100) == want
            end
            # Type stability: result is UnitRange{Int}.
            @test typeof(searchsortedrange(Auto(), v, 5.0, 7.0)) === UnitRange{Int}
        end

        @safetestset "queries_sorted kwarg" begin
            using FindFirstFunctions, StableRNGs
            v = collect(0.0:0.5:100.0)
            rng = StableRNG(2026)
            sorted_q = sort!(rand(rng, 64) .* 100.0)
            unsorted_q = rand(rng, 64) .* 100.0
            out = Vector{Int}(undef, 64)
            expected_sorted = searchsortedlast.(Ref(v), sorted_q)
            expected_unsorted = searchsortedlast.(Ref(v), unsorted_q)

            # Default behaviour (nothing) — runtime issorted check.
            searchsortedlast!(out, v, sorted_q; strategy = Auto())
            @test out == expected_sorted
            searchsortedlast!(out, v, unsorted_q; strategy = Auto())
            @test out == expected_unsorted

            # Explicit queries_sorted = true: trust the caller's sortedness.
            searchsortedlast!(out, v, sorted_q; strategy = Auto(), queries_sorted = true)
            @test out == expected_sorted
            # Across every shipped strategy.
            for strategy in (
                    LinearScan(), SIMDLinearScan(), BracketGallop(),
                    ExpFromLeft(), InterpolationSearch(), BinaryBracket(),
                )
                searchsortedlast!(
                    out, v, sorted_q;
                    strategy = strategy, queries_sorted = true
                )
                @test out == expected_sorted
                searchsortedfirst!(
                    out, v, sorted_q;
                    strategy = strategy, queries_sorted = true
                )
                @test out == searchsortedfirst.(Ref(v), sorted_q)
            end

            # Explicit queries_sorted = false: take the unsorted-loop path
            # unconditionally, even on sorted input — answers must still be
            # correct (the unsorted loop is per-query unhinted Base call).
            searchsortedlast!(out, v, sorted_q; strategy = Auto(), queries_sorted = false)
            @test out == expected_sorted
            searchsortedlast!(out, v, unsorted_q; strategy = Auto(), queries_sorted = false)
            @test out == expected_unsorted
        end

        @safetestset "SIMDLinearScan correctness" begin
            using FindFirstFunctions, StableRNGs
            F = FindFirstFunctions

            @testset "Int64 fuzz vs Base" begin
                rng = StableRNG(2026)
                for _ in 1:5_000
                    n = rand(rng, 1:512)
                    v = sort!(rand(rng, Int64(-1000):Int64(1000), n))
                    x = rand(rng, Int64(-1100):Int64(1100))
                    hint = rand(rng, 1:n)
                    @test searchsortedlast(F.SIMDLinearScan(), v, x, hint) ==
                        searchsortedlast(v, x)
                    @test searchsortedfirst(F.SIMDLinearScan(), v, x, hint) ==
                        searchsortedfirst(v, x)
                end
            end

            @testset "Float64 fuzz vs Base" begin
                rng = StableRNG(2027)
                for _ in 1:5_000
                    n = rand(rng, 1:512)
                    v = sort!(randn(rng, n))
                    x = (rand(rng) - 0.5) * 6
                    hint = rand(rng, 1:n)
                    @test searchsortedlast(F.SIMDLinearScan(), v, x, hint) ==
                        searchsortedlast(v, x)
                    @test searchsortedfirst(F.SIMDLinearScan(), v, x, hint) ==
                        searchsortedfirst(v, x)
                end
            end

            @testset "Edge cases (Int64)" begin
                v = collect(Int64, 1:100)
                # Out-of-range hint is clamped.
                @test searchsortedlast(F.SIMDLinearScan(), v, Int64(50), -5) == 50
                @test searchsortedlast(F.SIMDLinearScan(), v, Int64(50), 1_000) == 50
                # x below/above the range.
                @test searchsortedlast(F.SIMDLinearScan(), v, Int64(-10), 50) == 0
                @test searchsortedlast(F.SIMDLinearScan(), v, Int64(1_000), 50) == 100
                @test searchsortedfirst(F.SIMDLinearScan(), v, Int64(-10), 50) == 1
                @test searchsortedfirst(F.SIMDLinearScan(), v, Int64(1_000), 50) == 101
                # Empty and single-element vectors.
                vempty = Int64[]
                @test searchsortedlast(F.SIMDLinearScan(), vempty, Int64(5), 1) == 0
                @test searchsortedfirst(F.SIMDLinearScan(), vempty, Int64(5), 1) == 1
                v1 = Int64[42]
                @test searchsortedlast(F.SIMDLinearScan(), v1, Int64(42), 1) == 1
                @test searchsortedfirst(F.SIMDLinearScan(), v1, Int64(42), 1) == 1
                # Duplicates.
                vd = Int64[1, 2, 2, 2, 5]
                @test searchsortedlast(F.SIMDLinearScan(), vd, Int64(2), 1) == 4
                @test searchsortedfirst(F.SIMDLinearScan(), vd, Int64(2), 5) == 2
            end

            @testset "Fallback: non-Int64/Float64 eltypes" begin
                # Int32 vectors must hit the generic LinearScan fallback,
                # not the Int64 SIMD primitive.
                v32 = Int32[1, 5, 10, 20, 50, 100, 200]
                for x in (Int32(0), Int32(7), Int32(20), Int32(300))
                    for hint in 1:length(v32)
                        @test searchsortedlast(F.SIMDLinearScan(), v32, x, hint) ==
                            searchsortedlast(v32, x)
                        @test searchsortedfirst(F.SIMDLinearScan(), v32, x, hint) ==
                            searchsortedfirst(v32, x)
                    end
                end
                # Float32 same.
                v32f = Float32[1.0, 5.0, 10.0, 20.0, 50.0]
                for x in (Float32(0.0), Float32(7.0), Float32(20.0), Float32(100.0))
                    @test searchsortedlast(F.SIMDLinearScan(), v32f, x, 2) ==
                        searchsortedlast(v32f, x)
                end
                # Non-numeric.
                vs = sort!(["alpha", "beta", "gamma", "delta", "epsilon"])
                @test searchsortedlast(F.SIMDLinearScan(), vs, "gamma", 2) ==
                    searchsortedlast(vs, "gamma")
            end

            @testset "Fallback: no hint, reverse order" begin
                v = collect(Int64, 1:100)
                # No hint → BinaryBracket.
                @test searchsortedlast(F.SIMDLinearScan(), v, Int64(50)) ==
                    searchsortedlast(v, Int64(50))
                # Reverse order → scalar LinearScan.
                v_rev = collect(Int64, 100:-1:1)
                @test searchsortedlast(
                    F.SIMDLinearScan(), v_rev, Int64(50), 1; order = Base.Order.Reverse
                ) == searchsortedlast(v_rev, Int64(50), Base.Order.Reverse)
            end
        end

        @safetestset "findequal + BisectThenSIMD" begin
            using FindFirstFunctions, StableRNGs
            F = FindFirstFunctions

            # Reference: an Int sentinel-returning equality search built from
            # Base.searchsortedfirst.
            function ref_findequal(v, x)
                i = searchsortedfirst(v, x)
                return (i > lastindex(v) || !isequal(v[i], x)) ?
                    (firstindex(v) - 1) : i
            end

            @testset "Strategy parity on Int64 (1-based)" begin
                rng = StableRNG(3001)
                for _ in 1:2_000
                    n = rand(rng, 1:256)
                    v = sort!(rand(rng, Int64(-50):Int64(50), n))
                    x = rand(rng, Int64(-60):Int64(60))
                    hint = rand(rng, 1:n)
                    want = ref_findequal(v, x)
                    for strategy in (
                            F.BinaryBracket(), F.BracketGallop(),
                            F.SIMDLinearScan(), F.LinearScan(),
                            F.ExpFromLeft(), F.InterpolationSearch(),
                            F.Auto(), F.BisectThenSIMD(),
                        )
                        @test F.findequal(strategy, v, x) == want
                        @test F.findequal(strategy, v, x, hint) == want
                    end
                end
            end

            @testset "Strategy parity on Float64" begin
                rng = StableRNG(3002)
                for _ in 1:500
                    n = rand(rng, 1:256)
                    v = sort!(randn(rng, n))
                    # Mix queries that hit elements with ones that don't.
                    x = rand(rng) < 0.4 ? v[rand(rng, 1:n)] :
                        (rand(rng) - 0.5) * 6
                    hint = rand(rng, 1:n)
                    want = ref_findequal(v, x)
                    for strategy in (
                            F.BinaryBracket(), F.BracketGallop(),
                            F.SIMDLinearScan(), F.Auto(), F.BisectThenSIMD(),
                        )
                        @test F.findequal(strategy, v, x) == want
                        @test F.findequal(strategy, v, x, hint) == want
                    end
                end
            end

            @testset "BisectThenSIMD shortcut uses SIMD on DenseVector{Int64}" begin
                # Compare against findfirstsortedequal directly.
                v = collect(Int64, 1:10_000)
                for x in (
                        Int64(1), Int64(5_000), Int64(10_000),
                        Int64(0), Int64(10_001), Int64(-100), Int64(20_000),
                    )
                    a = F.findequal(F.BisectThenSIMD(), v, x)
                    b = F.findfirstsortedequal(x, v)
                    @test (a == 0 ? nothing : a) == b
                end
            end

            @testset "Sentinel for OffsetArray-style indexing" begin
                # Manually shift the index base by using a UnitRange directly.
                v = collect(Int64, 10:20)
                @test F.findequal(F.Auto(), v, Int64(15)) == 6
                @test F.findequal(F.Auto(), v, Int64(100)) == 0
                @test F.findequal(F.Auto(), v, Int64(-5)) == 0
            end

            @testset "Reverse ordering" begin
                v_rev = collect(Int64, 10:-1:1)
                # Forward findequal on a reverse-sorted vector with the
                # Reverse ordering should still find the element if present.
                @test F.findequal(
                    F.BinaryBracket(), v_rev, Int64(5);
                    order = Base.Order.Reverse,
                ) == 6
                @test F.findequal(
                    F.BinaryBracket(), v_rev, Int64(99);
                    order = Base.Order.Reverse,
                ) == 0
                # BisectThenSIMD on reverse order falls back to generic path.
                @test F.findequal(
                    F.BisectThenSIMD(), v_rev, Int64(5);
                    order = Base.Order.Reverse,
                ) == 6
            end

            @testset "Empty and single-element" begin
                vempty = Int64[]
                @test F.findequal(F.Auto(), vempty, Int64(0)) == 0
                @test F.findequal(F.BisectThenSIMD(), vempty, Int64(0)) == 0
                v1 = Int64[42]
                @test F.findequal(F.Auto(), v1, Int64(42)) == 1
                @test F.findequal(F.Auto(), v1, Int64(7)) == 0
                @test F.findequal(F.BisectThenSIMD(), v1, Int64(42)) == 1
            end

            @testset "BisectThenSIMD in positional dispatch falls back" begin
                # When used with searchsortedfirst/last, BisectThenSIMD just
                # delegates to BinaryBracket — its purpose is findequal.
                v = collect(Int64, 1:100)
                @test searchsortedfirst(F.BisectThenSIMD(), v, Int64(50)) ==
                    searchsortedfirst(v, Int64(50))
                @test searchsortedlast(F.BisectThenSIMD(), v, Int64(50)) ==
                    searchsortedlast(v, Int64(50))
            end
        end
    end

    if GROUP == "QA"
        activate_qa_env()
        @safetestset "Quality Assurance" include("qa/qa_tests.jl")
    end
end

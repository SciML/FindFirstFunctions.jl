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
            using FindFirstFunctions:
                Guesser, searchsortedfirstcorrelated,
                searchsortedlastcorrelated
            v = collect(LinRange(0, 10, 4))
            guesser_linear = Guesser(v)
            guesser_prev = Guesser(v, Ref(1), false)
            @test guesser_linear.linear_lookup
            @test searchsortedfirstcorrelated(v, 4.0, guesser_linear) == 3
            @test searchsortedfirstcorrelated(v, 1.4234326478e24, guesser_linear) == 5
            @test searchsortedlastcorrelated(v, 4.0, guesser_prev) == 2
            @test guesser_prev.idx_prev[] == 2

            # Edge case
            v1 = [42.0]
            guesser = Guesser(v1)
            @test guesser_linear.linear_lookup
            @test guesser(100) == 1
            @test guesser(42.0) == 1
            @test guesser(0) == 1
            @test searchsortedfirstcorrelated(v1, 0, guesser) == 1
            @test searchsortedfirstcorrelated(v1, 100, guesser) == 1 + 1  # see searchsortedfirst
            @test searchsortedfirstcorrelated(v1, 42.0, guesser) == 1
            @test searchsortedlastcorrelated(v1, 0, guesser) == 1 - 1 # see searchsortedlast
            @test searchsortedlastcorrelated(v1, 100, guesser) == 1
            @test searchsortedlastcorrelated(v1, 42.0, guesser) == 1
        end

        @safetestset "Custom ordering in searchsorted*correlated" begin
            using FindFirstFunctions:
                Guesser, searchsortedfirstcorrelated,
                searchsortedlastcorrelated

            # Test with reverse-sorted vector
            v_rev = collect(10.0:-1.0:1.0)  # [10.0, 9.0, ..., 1.0]

            # Test searchsortedfirstcorrelated with Reverse order
            @test searchsortedfirstcorrelated(v_rev, 5.0, 1; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 5.0, Base.Order.Reverse)
            @test searchsortedfirstcorrelated(v_rev, 10.0, 1; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 10.0, Base.Order.Reverse)
            @test searchsortedfirstcorrelated(v_rev, 1.0, 1; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 1.0, Base.Order.Reverse)
            @test searchsortedfirstcorrelated(v_rev, 0.0, 1; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 0.0, Base.Order.Reverse)
            @test searchsortedfirstcorrelated(v_rev, 11.0, 1; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 11.0, Base.Order.Reverse)

            # Test searchsortedlastcorrelated with Reverse order
            @test searchsortedlastcorrelated(v_rev, 5.0, 1; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 5.0, Base.Order.Reverse)
            @test searchsortedlastcorrelated(v_rev, 10.0, 1; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 10.0, Base.Order.Reverse)
            @test searchsortedlastcorrelated(v_rev, 1.0, 1; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 1.0, Base.Order.Reverse)
            @test searchsortedlastcorrelated(v_rev, 0.0, 1; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 0.0, Base.Order.Reverse)
            @test searchsortedlastcorrelated(v_rev, 11.0, 1; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 11.0, Base.Order.Reverse)

            # Test with Guesser and reverse order
            guesser_rev = Guesser(v_rev)
            @test searchsortedfirstcorrelated(v_rev, 5.0, guesser_rev; order = Base.Order.Reverse) ==
                searchsortedfirst(v_rev, 5.0, Base.Order.Reverse)
            @test searchsortedlastcorrelated(v_rev, 5.0, guesser_rev; order = Base.Order.Reverse) ==
                searchsortedlast(v_rev, 5.0, Base.Order.Reverse)

            # Test that default order (Forward) still works correctly
            v_fwd = collect(1.0:1.0:10.0)  # [1.0, 2.0, ..., 10.0]
            @test searchsortedfirstcorrelated(v_fwd, 5.0, 1) ==
                searchsortedfirst(v_fwd, 5.0)
            @test searchsortedlastcorrelated(v_fwd, 5.0, 1) ==
                searchsortedlast(v_fwd, 5.0)
        end

        @safetestset "Exponential Search (searchsortedfirstexp)" begin
            using FindFirstFunctions: searchsortedfirstexp

            # Basic functionality - should match searchsortedfirst
            v = collect(1:100)
            for x in [1, 5, 10, 50, 99, 100]
                @test searchsortedfirstexp(v, x) == searchsortedfirst(v, x)
            end

            # Edge cases - value not in array
            @test searchsortedfirstexp(v, 0) == searchsortedfirst(v, 0)
            @test searchsortedfirstexp(v, 101) == searchsortedfirst(v, 101)
            @test searchsortedfirstexp(v, 50.5) == searchsortedfirst(v, 50.5)

            # With custom bounds
            @test searchsortedfirstexp(v, 50, 40, 60) == searchsortedfirst(v, 50, 40, 60, Base.Order.Forward)
            @test searchsortedfirstexp(v, 45, 40, 60) == searchsortedfirst(v, 45, 40, 60, Base.Order.Forward)

            # Float vectors
            vf = collect(0.0:0.1:10.0)
            for x in [0.0, 0.5, 1.0, 5.0, 9.9, 10.0]
                @test searchsortedfirstexp(vf, x) == searchsortedfirst(vf, x)
            end

            # Empty and small vectors
            @test searchsortedfirstexp(Int[], 5) == 1
            @test searchsortedfirstexp([1], 0) == 1
            @test searchsortedfirstexp([1], 1) == 1
            @test searchsortedfirstexp([1], 2) == 2

            # Vector with repeated elements
            vr = [1, 2, 2, 2, 3, 4, 5]
            @test searchsortedfirstexp(vr, 2) == searchsortedfirst(vr, 2)

            # Large vector
            big_v = collect(1:10000)
            for x in [1, 100, 1000, 5000, 9999, 10000]
                @test searchsortedfirstexp(big_v, x) == searchsortedfirst(big_v, x)
            end
        end

        @safetestset "Vectorized Search (searchsortedfirstvec and searchsortedlastvec)" begin
            using FindFirstFunctions: searchsortedfirstvec, searchsortedlastvec

            # Basic functionality
            v = collect(1:100)
            x_sorted = [5, 10, 20, 50, 90]

            # searchsortedfirstvec should match element-wise searchsortedfirst
            result_first = searchsortedfirstvec(v, x_sorted)
            expected_first = searchsortedfirst.(Ref(v), x_sorted)
            @test result_first == expected_first

            # searchsortedlastvec should match element-wise searchsortedlast
            result_last = searchsortedlastvec(v, x_sorted)
            expected_last = searchsortedlast.(Ref(v), x_sorted)
            @test result_last == expected_last

            # Unsorted input falls back to element-wise
            x_unsorted = [50, 10, 90, 5, 20]
            @test searchsortedfirstvec(v, x_unsorted) == searchsortedfirst.(Ref(v), x_unsorted)
            @test searchsortedlastvec(v, x_unsorted) == searchsortedlast.(Ref(v), x_unsorted)

            # Float vectors
            vf = collect(0.0:0.1:10.0)
            xf_sorted = [0.5, 1.0, 2.5, 5.0, 9.5]
            @test searchsortedfirstvec(vf, xf_sorted) == searchsortedfirst.(Ref(vf), xf_sorted)
            @test searchsortedlastvec(vf, xf_sorted) == searchsortedlast.(Ref(vf), xf_sorted)

            # Edge cases - values outside range
            x_edges = [-5, 0, 1, 100, 150]
            @test searchsortedfirstvec(v, x_edges) == searchsortedfirst.(Ref(v), x_edges)
            @test searchsortedlastvec(v, x_edges) == searchsortedlast.(Ref(v), x_edges)

            # Empty input vector
            @test searchsortedfirstvec(v, Int[]) == Int[]
            @test searchsortedlastvec(v, Int[]) == Int[]

            # Single element search
            @test searchsortedfirstvec(v, [50]) == [50]
            @test searchsortedlastvec(v, [50]) == [50]

            # Values between grid points
            x_between = [1.5, 10.5, 50.5, 99.5]
            @test searchsortedfirstvec(v, x_between) == searchsortedfirst.(Ref(v), x_between)
            @test searchsortedlastvec(v, x_between) == searchsortedlast.(Ref(v), x_between)
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

        @safetestset "Batched in-place searchsorted!" begin
            using FindFirstFunctions:
                LinearScan, BracketGallop, BinaryBracket, Auto,
                searchsortedlast!, searchsortedfirst!,
                searchsortedlastvec, searchsortedfirstvec

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

            # Existing allocating wrappers still work
            @test searchsortedlastvec(v, x_sorted) ==
                searchsortedlast.(Ref(v), x_sorted)
            @test searchsortedfirstvec(v, x_sorted) ==
                searchsortedfirst.(Ref(v), x_sorted)
            @test searchsortedlastvec(v, x_unsorted) ==
                searchsortedlast.(Ref(v), x_unsorted)
        end
    end

    if GROUP == "QA"
        activate_qa_env()
        @safetestset "Quality Assurance" include("qa/qa_tests.jl")
    end
end

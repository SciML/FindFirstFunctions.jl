using SafeTestsets, Test

@testset "FindFirstFunctions" begin
    @safetestset "Quality Assurance" include("qa.jl")

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

    if get(ENV, "GROUP", "all") == "all" || get(ENV, "GROUP", "all") == "nopre"
        @safetestset "Allocation Tests" include("alloc_tests.jl")
    end
end

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
end

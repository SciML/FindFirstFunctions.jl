using AllocCheck
using FindFirstFunctions
using Test

@testset "AllocCheck - Zero Allocations" begin
    # Test data
    small_vec = Int64.(1:16)
    medium_vec = Int64.(1:128)
    large_vec = Int64.(1:1000)
    sorted_float_vec = collect(1.0:0.1:100.0)
    linear_vec = collect(LinRange(0.0, 100.0, 1000))

    @testset "findfirstequal" begin
        # Warm up
        FindFirstFunctions.findfirstequal(Int64(8), small_vec)

        # Test zero allocations for different vector sizes
        @test (@allocated FindFirstFunctions.findfirstequal(Int64(8), small_vec)) == 0
        @test (@allocated FindFirstFunctions.findfirstequal(Int64(64), medium_vec)) == 0
        @test (@allocated FindFirstFunctions.findfirstequal(Int64(500), large_vec)) == 0
        # Not found case
        @test (@allocated FindFirstFunctions.findfirstequal(Int64(9999), small_vec)) == 0
    end

    @testset "findfirstsortedequal" begin
        # Warm up
        FindFirstFunctions.findfirstsortedequal(Int64(8), small_vec)

        # Test zero allocations
        @test (@allocated FindFirstFunctions.findfirstsortedequal(Int64(8), small_vec)) == 0
        @test (@allocated FindFirstFunctions.findfirstsortedequal(Int64(64), medium_vec)) == 0
        @test (@allocated FindFirstFunctions.findfirstsortedequal(Int64(500), large_vec)) == 0
        # Not found case
        @test (@allocated FindFirstFunctions.findfirstsortedequal(Int64(9999), small_vec)) == 0
    end

    @testset "bracketstrictlymontonic" begin
        # Warm up
        FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 1, Base.Order.Forward)

        # Test zero allocations
        @test (@allocated FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 1, Base.Order.Forward)) == 0
        @test (@allocated FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 500, Base.Order.Forward)) == 0
    end

    @testset "looks_linear" begin
        # Warm up
        FindFirstFunctions.looks_linear(linear_vec)

        # Test zero allocations
        @test (@allocated FindFirstFunctions.looks_linear(linear_vec)) == 0
        @test (@allocated FindFirstFunctions.looks_linear(sorted_float_vec)) == 0
    end

    @testset "Guesser" begin
        guesser = FindFirstFunctions.Guesser(linear_vec)

        # Warm up
        guesser(50.0)

        # Test zero allocations for Guesser call
        @test (@allocated guesser(50.0)) == 0
        @test (@allocated guesser(25.0)) == 0
    end

    @testset "searchsortedfirstcorrelated" begin
        # Warm up
        FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 1)
        FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 500)

        # Test zero allocations with integer guess
        @test (@allocated FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 1)) == 0
        @test (@allocated FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 500)) == 0
    end

    @testset "searchsortedlastcorrelated" begin
        # Warm up
        FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 1)
        FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 500)

        # Test zero allocations with integer guess
        @test (@allocated FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 1)) == 0
        @test (@allocated FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 500)) == 0
    end

    @testset "searchsortedfirstexp" begin
        # Warm up
        FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0)
        FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0, 490, 510)

        # Test zero allocations
        @test (@allocated FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0)) == 0
        @test (@allocated FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0, 490, 510)) == 0
    end
end

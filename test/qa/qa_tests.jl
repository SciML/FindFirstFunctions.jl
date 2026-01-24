using FindFirstFunctions, Aqua, ExplicitImports, JET, AllocCheck, Test

@testset "Aqua" begin
    Aqua.find_persistent_tasks_deps(FindFirstFunctions)
    Aqua.test_ambiguities(FindFirstFunctions, recursive = false)
    Aqua.test_deps_compat(FindFirstFunctions)
    Aqua.test_piracies(FindFirstFunctions)
    Aqua.test_project_extras(FindFirstFunctions)
    Aqua.test_stale_deps(FindFirstFunctions)
    Aqua.test_unbound_args(FindFirstFunctions)
    Aqua.test_undefined_exports(FindFirstFunctions)
end

@testset "ExplicitImports" begin
    @test check_no_implicit_imports(FindFirstFunctions) === nothing
    @test check_no_stale_explicit_imports(FindFirstFunctions) === nothing
end

@testset "JET static analysis" begin
    # Test key entry points for type stability and potential runtime errors
    vec_int64 = Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    vec_float64 = Float64[1.0, 2.0, 3.0, 4.0, 5.0]

    # findfirstequal - fast SIMD-based search
    rep = JET.report_call(FindFirstFunctions.findfirstequal, (Int64, Vector{Int64}))
    @test length(JET.get_reports(rep)) == 0

    # findfirstsortedequal - binary search variant
    rep = JET.report_call(FindFirstFunctions.findfirstsortedequal, (Int64, Vector{Int64}))
    @test length(JET.get_reports(rep)) == 0

    # bracketstrictlymontonic - bracketing for sorted vectors
    rep = JET.report_call(
        FindFirstFunctions.bracketstrictlymontonic,
        (Vector{Int64}, Int64, Int64, Base.Order.ForwardOrdering)
    )
    @test length(JET.get_reports(rep)) == 0

    # looks_linear - linearity check
    rep = JET.report_call(FindFirstFunctions.looks_linear, (Vector{Float64},))
    @test length(JET.get_reports(rep)) == 0

    # Guesser - test constructor and callable
    guesser = FindFirstFunctions.Guesser(vec_float64)
    rep = JET.report_call(guesser, (Float64,))
    @test length(JET.get_reports(rep)) == 0

    # searchsortedfirstcorrelated with Integer guess
    rep = JET.report_call(
        FindFirstFunctions.searchsortedfirstcorrelated,
        (Vector{Int64}, Int64, Int64)
    )
    @test length(JET.get_reports(rep)) == 0

    # searchsortedlastcorrelated with Integer guess
    rep = JET.report_call(
        FindFirstFunctions.searchsortedlastcorrelated,
        (Vector{Int64}, Int64, Int64)
    )
    @test length(JET.get_reports(rep)) == 0

    # searchsortedfirstexp - exponential search
    rep = JET.report_call(
        FindFirstFunctions.searchsortedfirstexp,
        (Vector{Int64}, Int64, Int64, Int64)
    )
    @test length(JET.get_reports(rep)) == 0

    # searchsortedfirstvec - vectorized search
    rep = JET.report_call(
        FindFirstFunctions.searchsortedfirstvec,
        (Vector{Int64}, Vector{Int64})
    )
    @test length(JET.get_reports(rep)) == 0

    # searchsortedlastvec - vectorized search
    rep = JET.report_call(
        FindFirstFunctions.searchsortedlastvec,
        (Vector{Int64}, Vector{Int64})
    )
    @test length(JET.get_reports(rep)) == 0
end

@testset "AllocCheck - Zero Allocations" begin
    # Test data
    small_vec = Int64.(1:16)
    medium_vec = Int64.(1:128)
    large_vec = Int64.(1:1000)
    sorted_float_vec = collect(1.0:0.1:100.0)
    linear_vec = collect(LinRange(0.0, 100.0, 1000))

    @testset "findfirstequal" begin
        # Warm up all cases to avoid JIT/GC measurement artifacts
        FindFirstFunctions.findfirstequal(Int64(8), small_vec)
        FindFirstFunctions.findfirstequal(Int64(64), medium_vec)
        FindFirstFunctions.findfirstequal(Int64(500), large_vec)
        FindFirstFunctions.findfirstequal(Int64(9999), small_vec)

        # Test zero allocations for different vector sizes
        # Use minimum over multiple runs to filter out GC noise (Julia 1.12+)
        @test minimum(@allocated(FindFirstFunctions.findfirstequal(Int64(8), small_vec)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.findfirstequal(Int64(64), medium_vec)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.findfirstequal(Int64(500), large_vec)) for _ in 1:10) == 0
        # Not found case
        @test minimum(@allocated(FindFirstFunctions.findfirstequal(Int64(9999), small_vec)) for _ in 1:10) == 0
    end

    @testset "findfirstsortedequal" begin
        # Warm up all cases to avoid JIT/GC measurement artifacts
        FindFirstFunctions.findfirstsortedequal(Int64(8), small_vec)
        FindFirstFunctions.findfirstsortedequal(Int64(64), medium_vec)
        FindFirstFunctions.findfirstsortedequal(Int64(500), large_vec)
        FindFirstFunctions.findfirstsortedequal(Int64(9999), small_vec)

        # Test zero allocations
        # Use minimum over multiple runs to filter out GC noise (Julia 1.12+)
        @test minimum(@allocated(FindFirstFunctions.findfirstsortedequal(Int64(8), small_vec)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.findfirstsortedequal(Int64(64), medium_vec)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.findfirstsortedequal(Int64(500), large_vec)) for _ in 1:10) == 0
        # Not found case
        @test minimum(@allocated(FindFirstFunctions.findfirstsortedequal(Int64(9999), small_vec)) for _ in 1:10) == 0
    end

    @testset "bracketstrictlymontonic" begin
        # Warm up
        FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 1, Base.Order.Forward)
        FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 500, Base.Order.Forward)

        # Test zero allocations
        @test minimum(@allocated(FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 1, Base.Order.Forward)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.bracketstrictlymontonic(linear_vec, 50.0, 500, Base.Order.Forward)) for _ in 1:10) == 0
    end

    @testset "looks_linear" begin
        # Warm up
        FindFirstFunctions.looks_linear(linear_vec)
        FindFirstFunctions.looks_linear(sorted_float_vec)

        # Test zero allocations
        @test minimum(@allocated(FindFirstFunctions.looks_linear(linear_vec)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.looks_linear(sorted_float_vec)) for _ in 1:10) == 0
    end

    @testset "Guesser" begin
        guesser = FindFirstFunctions.Guesser(linear_vec)

        # Warm up
        guesser(50.0)
        guesser(25.0)

        # Test zero allocations for Guesser call
        @test minimum(@allocated(guesser(50.0)) for _ in 1:10) == 0
        @test minimum(@allocated(guesser(25.0)) for _ in 1:10) == 0
    end

    @testset "searchsortedfirstcorrelated" begin
        # Warm up
        FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 1)
        FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 500)

        # Test zero allocations with integer guess
        @test minimum(@allocated(FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 1)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.searchsortedfirstcorrelated(linear_vec, 50.0, 500)) for _ in 1:10) == 0
    end

    @testset "searchsortedlastcorrelated" begin
        # Warm up
        FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 1)
        FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 500)

        # Test zero allocations with integer guess
        @test minimum(@allocated(FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 1)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.searchsortedlastcorrelated(linear_vec, 50.0, 500)) for _ in 1:10) == 0
    end

    @testset "searchsortedfirstexp" begin
        # Warm up
        FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0)
        FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0, 490, 510)

        # Test zero allocations
        @test minimum(@allocated(FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0)) for _ in 1:10) == 0
        @test minimum(@allocated(FindFirstFunctions.searchsortedfirstexp(linear_vec, 50.0, 490, 510)) for _ in 1:10) == 0
    end
end

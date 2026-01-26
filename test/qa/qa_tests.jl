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

@testset "AllocCheck - Static Allocation Analysis" begin
    # Use AllocCheck's static analysis (check_allocs) instead of runtime @allocated.
    # This is more robust as it analyzes LLVM IR for allocation sites rather than
    # measuring runtime allocations which can be noisy due to GC artifacts.

    @testset "findfirstequal" begin
        # Int64 vector (SIMD path)
        allocs = check_allocs(FindFirstFunctions.findfirstequal, (Int64, Vector{Int64}))
        @test isempty(allocs)
    end

    @testset "findfirstsortedequal" begin
        # Int64 vector (binary search + SIMD)
        allocs = check_allocs(FindFirstFunctions.findfirstsortedequal, (Int64, Vector{Int64}))
        @test isempty(allocs)
    end

    @testset "bracketstrictlymontonic" begin
        # Int64 vector with Forward ordering
        allocs = check_allocs(
            FindFirstFunctions.bracketstrictlymontonic,
            (Vector{Int64}, Int64, Int64, Base.Order.ForwardOrdering)
        )
        @test isempty(allocs)

        # Float64 vector with Forward ordering
        allocs = check_allocs(
            FindFirstFunctions.bracketstrictlymontonic,
            (Vector{Float64}, Float64, Int64, Base.Order.ForwardOrdering)
        )
        @test isempty(allocs)
    end

    @testset "looks_linear" begin
        # Float64 vector
        allocs = check_allocs(FindFirstFunctions.looks_linear, (Vector{Float64},))
        @test isempty(allocs)

        # Int64 vector
        allocs = check_allocs(FindFirstFunctions.looks_linear, (Vector{Int64},))
        @test isempty(allocs)
    end

    @testset "Guesser callable" begin
        # Test the Guesser callable with Float64 input
        # Note: We test a concrete Guesser type, not the constructor
        GuesserType = FindFirstFunctions.Guesser{Vector{Float64}}
        allocs = check_allocs(
            (g, x) -> g(x),
            (GuesserType, Float64)
        )
        @test isempty(allocs)
    end

    @testset "searchsortedfirstcorrelated" begin
        # Int64 vector with integer guess
        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstcorrelated,
            (Vector{Int64}, Int64, Int64)
        )
        @test isempty(allocs)

        # Float64 vector with integer guess
        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstcorrelated,
            (Vector{Float64}, Float64, Int64)
        )
        @test isempty(allocs)
    end

    @testset "searchsortedlastcorrelated" begin
        # Int64 vector with integer guess
        allocs = check_allocs(
            FindFirstFunctions.searchsortedlastcorrelated,
            (Vector{Int64}, Int64, Int64)
        )
        @test isempty(allocs)

        # Float64 vector with integer guess
        allocs = check_allocs(
            FindFirstFunctions.searchsortedlastcorrelated,
            (Vector{Float64}, Float64, Int64)
        )
        @test isempty(allocs)
    end

    @testset "searchsortedfirstexp" begin
        # Int64 vector
        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstexp,
            (Vector{Int64}, Int64, Int64, Int64)
        )
        @test isempty(allocs)

        # Float64 vector
        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstexp,
            (Vector{Float64}, Float64, Int64, Int64)
        )
        @test isempty(allocs)
    end
end

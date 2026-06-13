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
    vec_int64 = Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    vec_float64 = Float64[1.0, 2.0, 3.0, 4.0, 5.0]

    # findfirstequal - fast SIMD-based search
    rep = JET.report_call(FindFirstFunctions.findfirstequal, (Int64, Vector{Int64}))
    @test length(JET.get_reports(rep)) == 0

    # findfirstsortedequal - binary search variant
    rep = JET.report_call(FindFirstFunctions.findfirstsortedequal, (Int64, Vector{Int64}))
    @test length(JET.get_reports(rep)) == 0

    # bracketstrictlymonotonic - bracketing for sorted vectors
    rep = JET.report_call(
        FindFirstFunctions.bracketstrictlymonotonic,
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

    # searchsorted_last with each StrategyKind - the v3 enum-dispatch hot path.
    for kind in (
            KIND_BINARY_BRACKET, KIND_LINEAR_SCAN, KIND_BRACKET_GALLOP,
            KIND_EXP_FROM_LEFT, KIND_INTERPOLATION_SEARCH,
        )
        rep = JET.report_call(
            (k, v, x, h) -> FindFirstFunctions.searchsorted_last(k, v, x, h),
            (typeof(kind), Vector{Int64}, Int64, Int64),
        )
        @test length(JET.get_reports(rep)) == 0
    end

    # searchsorted_first with each StrategyKind
    for kind in (
            KIND_BINARY_BRACKET, KIND_LINEAR_SCAN, KIND_BRACKET_GALLOP,
            KIND_EXP_FROM_LEFT, KIND_INTERPOLATION_SEARCH,
        )
        rep = JET.report_call(
            (k, v, x, h) -> FindFirstFunctions.searchsorted_first(k, v, x, h),
            (typeof(kind), Vector{Int64}, Int64, Int64),
        )
        @test length(JET.get_reports(rep)) == 0
    end

    # searchsortedfirstexp - exponential search helper (internal)
    rep = JET.report_call(
        FindFirstFunctions.searchsortedfirstexp,
        (Vector{Int64}, Int64, Int64, Int64)
    )
    @test length(JET.get_reports(rep)) == 0

    # Batched API
    rep = JET.report_call(
        FindFirstFunctions.searchsortedlast!,
        (Vector{Int}, Vector{Int64}, Vector{Int64}),
    )
    @test length(JET.get_reports(rep)) == 0
end

@testset "AllocCheck - Static Allocation Analysis" begin
    @testset "findfirstequal" begin
        allocs = check_allocs(FindFirstFunctions.findfirstequal, (Int64, Vector{Int64}))
        @test isempty(allocs)
    end

    @testset "findfirstsortedequal" begin
        allocs = check_allocs(FindFirstFunctions.findfirstsortedequal, (Int64, Vector{Int64}))
        @test isempty(allocs)
    end

    @testset "bracketstrictlymonotonic" begin
        allocs = check_allocs(
            FindFirstFunctions.bracketstrictlymonotonic,
            (Vector{Int64}, Int64, Int64, Base.Order.ForwardOrdering)
        )
        @test isempty(allocs)

        allocs = check_allocs(
            FindFirstFunctions.bracketstrictlymonotonic,
            (Vector{Float64}, Float64, Int64, Base.Order.ForwardOrdering)
        )
        @test isempty(allocs)
    end

    @testset "looks_linear" begin
        allocs = check_allocs(FindFirstFunctions.looks_linear, (Vector{Float64},))
        @test isempty(allocs)

        allocs = check_allocs(FindFirstFunctions.looks_linear, (Vector{Int64},))
        @test isempty(allocs)
    end

    @testset "Guesser callable" begin
        GuesserType = FindFirstFunctions.Guesser{Vector{Float64}}
        allocs = check_allocs(
            (g, x) -> g(x),
            (GuesserType, Float64)
        )
        @test isempty(allocs)
    end

    @testset "searchsorted_last via enum tag" begin
        # Each kind on Int64 / Float64 dense vectors: no allocations.
        for kind in (
                KIND_BINARY_BRACKET, KIND_LINEAR_SCAN,
                KIND_BRACKET_GALLOP, KIND_EXP_FROM_LEFT,
            )
            allocs = check_allocs(
                (k, v, x, h) -> FindFirstFunctions.searchsorted_last(k, v, x, h),
                (typeof(kind), Vector{Int64}, Int64, Int64),
            )
            @test isempty(allocs)
            allocs = check_allocs(
                (k, v, x, h) -> FindFirstFunctions.searchsorted_first(k, v, x, h),
                (typeof(kind), Vector{Int64}, Int64, Int64),
            )
            @test isempty(allocs)
        end
    end

    @testset "searchsortedfirstexp" begin
        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstexp,
            (Vector{Int64}, Int64, Int64, Int64)
        )
        @test isempty(allocs)

        allocs = check_allocs(
            FindFirstFunctions.searchsortedfirstexp,
            (Vector{Float64}, Float64, Int64, Int64)
        )
        @test isempty(allocs)
    end
end

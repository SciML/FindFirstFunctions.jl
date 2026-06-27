using FindFirstFunctions, JET, AllocCheck, Test

# Beyond the package-wide JET pass in run_qa (qa.jl), assert type stability on the
# specific hot-path call signatures, and assert they allocate nothing — guarantees
# `JET.test_package` / `Aqua` do not make on their own.

@testset "JET static analysis (hot-path signatures)" begin
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
        # Each kind on Int64 dense vectors: no allocations.
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

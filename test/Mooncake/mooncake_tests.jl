@safetestset "Mooncake extension: searches are inactive" begin
    using FindFirstFunctions, Mooncake, Test

    function interp(u, knots, x)
        i0 = searchsorted_last(KIND_BINARY_BRACKET, knots, x)
        i = clamp(i0, 1, length(knots) - 1)
        w = (x - knots[i]) / (knots[i + 1] - knots[i])
        return (1 - w) * u[i] + w * u[i + 1]
    end

    knots = collect(0.0:0.5:10.0)
    u = sin.(knots)
    x = 3.3

    iref = searchsorted_last(KIND_BINARY_BRACKET, knots, x)
    wref = (x - knots[iref]) / (knots[iref + 1] - knots[iref])

    @testset "reverse mode, gradient w.r.t. the knot values" begin
        f(u) = interp(u, knots, x)
        _, (_, du) = Mooncake.value_and_gradient!!(Mooncake.build_rrule(f, u), f, u)
        expected = zero(u)
        expected[iref] = 1 - wref
        expected[iref + 1] = wref
        @test du ≈ expected
    end

    @testset "reverse mode, derivative w.r.t. the query point" begin
        g(x) = interp(u, knots, x)
        _, (_, dx) = Mooncake.value_and_gradient!!(Mooncake.build_rrule(g, x), g, x)
        @test dx ≈ (u[iref + 1] - u[iref]) / (knots[iref + 1] - knots[iref])
    end

    @testset "forward mode agrees" begin
        g(x) = interp(u, knots, x)
        cache = Mooncake.prepare_derivative_cache(g, x)
        _, dx = Mooncake.value_and_derivative!!(cache, (g, Mooncake.NoTangent()), (x, 1.0))
        @test dx ≈ (u[iref + 1] - u[iref]) / (knots[iref + 1] - knots[iref])
    end

    # The motivating case (SciMLSensitivity.jl#1648): native forward-over-reverse HVP
    # needs both directions to work through the same search, since it forward-
    # differentiates the whole reverse pass.
    @testset "native HVP w.r.t. the knot values" begin
        f(u) = interp(u, knots, x)
        hcache = Mooncake.prepare_hvp_cache(f, u)
        v = zero(u)
        v[iref] = 1.0
        _, du, hvp_u = Mooncake.value_and_hvp!!(hcache, f, v, u)
        expected = zero(u)
        expected[iref] = 1 - wref
        expected[iref + 1] = wref
        @test du ≈ expected
        # `interp` is linear in `u`, so the Hessian w.r.t. `u` is exactly zero.
        @test all(iszero, hvp_u)
    end

    # Regression test for the actual bug (SciMLSensitivity.jl#1648): `KIND_SIMD_LINEAR_SCAN`
    # specifically is the strategy whose kernel embeds a raw `llvmcall` that Mooncake cannot
    # translate. `KIND_BINARY_BRACKET` above never reaches that kernel at all, so it alone
    # would not catch a regression here.
    @testset "KIND_SIMD_LINEAR_SCAN specifically" begin
        function interp_simd(u, knots, x)
            i0 = searchsorted_last(KIND_SIMD_LINEAR_SCAN, knots, x)
            i = clamp(i0, 1, length(knots) - 1)
            w = (x - knots[i]) / (knots[i + 1] - knots[i])
            return (1 - w) * u[i] + w * u[i + 1]
        end
        f(u) = interp_simd(u, knots, x)
        _, (_, du) = Mooncake.value_and_gradient!!(Mooncake.build_rrule(f, u), f, u)
        hcache = Mooncake.prepare_hvp_cache(f, u)
        v = zero(u)
        v[iref] = 1.0
        _, du2, hvp_u = Mooncake.value_and_hvp!!(hcache, f, v, u)
        expected = zero(u)
        expected[iref] = 1 - wref
        expected[iref + 1] = wref
        @test du ≈ expected
        @test du2 ≈ expected
        @test all(iszero, hvp_u)
    end

    @testset "batched and equality searches accept the rule" begin
        function g(u, knots, xs)
            idx = similar(xs, Int)
            searchsortedlast!(idx, knots, xs)
            j = findfirstsortedequal(knots[3], knots)
            return sum(u) + zero(eltype(u)) * (idx[1] + something(j, 0))
        end
        xs = [0.7, 2.2, 9.1]
        h(u) = g(u, knots, xs)
        _, (_, du) = Mooncake.value_and_gradient!!(Mooncake.build_rrule(h, u), h, u)
        @test all(==(1.0), du)
    end
end

@safetestset "EnzymeCore extension: searches are inactive" begin
    using FindFirstFunctions, Enzyme, Test

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
        du = zero(u)
        Enzyme.autodiff(Reverse, interp, Active, Duplicated(u, du), Const(knots), Const(x))
        expected = zero(u)
        expected[iref] = 1 - wref
        expected[iref + 1] = wref
        @test du ≈ expected
    end

    @testset "reverse mode, derivative w.r.t. the query point" begin
        # The search runs on the active input `x`; only the linear weight
        # contributes, with slope (u[i+1] - u[i]) / h.
        dx = Enzyme.autodiff(Reverse, interp, Active, Const(u), Const(knots), Active(x))[1][3]
        @test dx ≈ (u[iref + 1] - u[iref]) / (knots[iref + 1] - knots[iref])
    end

    @testset "forward mode agrees" begin
        dx = Enzyme.autodiff(Forward, interp, Duplicated, Const(u), Const(knots), Duplicated(x, 1.0))[1]
        @test dx ≈ (u[iref + 1] - u[iref]) / (knots[iref + 1] - knots[iref])
    end

    @testset "batched and equality searches accept the rule" begin
        function g(u, knots, xs)
            idx = similar(xs, Int)
            searchsortedlast!(idx, knots, xs)
            j = findfirstsortedequal(knots[3], knots)
            return sum(u) + zero(eltype(u)) * (idx[1] + something(j, 0))
        end
        xs = [0.7, 2.2, 9.1]
        du = zero(u)
        Enzyme.autodiff(Reverse, g, Active, Duplicated(u, du), Const(knots), Const(xs))
        @test all(==(1.0), du)
    end
end

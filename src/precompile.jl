# PrecompileTools workload — exercises the most commonly used public
# entry points across typical eltypes so `using FindFirstFunctions` is hot
# without a startup compile spike on the first call.

using PrecompileTools: @compile_workload, @setup_workload

@setup_workload begin
    vec_int64 = Int64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    linear_vec = collect(1.0:0.5:10.0)

    @compile_workload begin
        # findfirstequal: fast SIMD-based search in Int64 vectors.
        findfirstequal(Int64(5), vec_int64)
        findfirstequal(Int64(100), vec_int64)

        # findfirstsortedequal: binary search in sorted Int64 vectors.
        findfirstsortedequal(Int64(8), vec_int64)
        findfirstsortedequal(Int64(100), vec_int64)

        # looks_linear: check if vector is evenly spaced.
        looks_linear(linear_vec)

        # Guesser: hint provider for correlated repeated searches.
        guesser = Guesser(linear_vec)
        guesser(5.0)

        # Strategy dispatch — single-query forms across the standard strategies.
        for strategy in (
                LinearScan(), SIMDLinearScan(), BracketGallop(), ExpFromLeft(),
                InterpolationSearch(), BinaryBracket(), Auto(),
                Auto(SearchProperties(linear_vec)),
                Auto(linear_vec),
            )
            searchsortedfirst(strategy, vec_int64, Int64(8), Int64(1))
            searchsortedlast(strategy, vec_int64, Int64(8), Int64(1))
        end
        # Auto-with-uniform-range — exercises the props-aware UniformStep kernel.
        let r = 0.0:0.5:10.0
            auto_r = Auto(r)
            searchsortedlast(auto_r, r, 3.7)
            searchsortedfirst(auto_r, r, 3.7)
            searchsortedlast(auto_r, r, 3.7, 1)
        end
        # findequal: generic + BisectThenSIMD shortcut for Int64 dense vectors.
        for strategy in (
                BinaryBracket(), BracketGallop(), SIMDLinearScan(),
                BisectThenSIMD(), Auto(),
            )
            findequal(strategy, vec_int64, Int64(8))
            findequal(strategy, vec_int64, Int64(8), Int64(1))
        end
        # SIMDLinearScan's Float64 specialization.
        let vec_f64 = collect(1.0:1.0:16.0)
            searchsortedfirst(SIMDLinearScan(), vec_f64, 8.0, 1)
            searchsortedlast(SIMDLinearScan(), vec_f64, 8.0, 1)
        end
        searchsortedfirst(GuesserHint(Guesser(vec_int64)), vec_int64, Int64(8))
        searchsortedlast(GuesserHint(Guesser(vec_int64)), vec_int64, Int64(8))

        # Strategy dispatch — batched in-place forms.
        idx_out = Vector{Int}(undef, 4)
        queries = Int64[2, 5, 8, 12]
        searchsortedfirst!(idx_out, vec_int64, queries)
        searchsortedlast!(idx_out, vec_int64, queries)
    end
end

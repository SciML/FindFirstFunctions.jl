using SciMLTesting, FindFirstFunctions, JET, Test

run_qa(
    FindFirstFunctions;
    explicit_imports = true,
    ei_kwargs = (;
        # All six are Base internals accessed by qualification (GC.@preserve,
        # Base.@propagate_inbounds, Base.Order, Base.RefValue, Base.libllvm_version,
        # Base.llvmcall). They are not public API, so ExplicitImports flags the
        # qualified accesses; there is no public replacement.  Source pkg: Base.
        all_qualified_accesses_are_public = (;
            ignore = (
                Symbol("@preserve"),
                Symbol("@propagate_inbounds"),
                :Order,
                :RefValue,
                :libllvm_version,
                :llvmcall,
            ),
        ),
    ),
)

@testset "Public API documentation coverage" begin
    public_names = setdiff(
        Set(names(FindFirstFunctions; all = false, imported = false)),
        Set((nameof(FindFirstFunctions),)),
    )

    documented_names = Set{Symbol}()
    for binding in keys(Base.Docs.meta(FindFirstFunctions))
        binding.mod === FindFirstFunctions && push!(documented_names, binding.var)
    end

    docs_names = Set{Symbol}()
    docs_dir = joinpath(pkgdir(FindFirstFunctions), "docs", "src")
    for file in readdir(docs_dir; join = true)
        endswith(file, ".md") || continue
        in_docs_block = false
        for line in eachline(file)
            stripped = strip(line)
            if startswith(stripped, "```@docs")
                in_docs_block = true
            elseif in_docs_block && startswith(stripped, "```")
                in_docs_block = false
            elseif in_docs_block
                m = match(r"^FindFirstFunctions\.([A-Za-z_][A-Za-z_0-9!]*$)", stripped)
                m === nothing || push!(docs_names, Symbol(m.captures[1]))
            end
        end
    end

    @test isempty(setdiff(public_names, documented_names))
    @test isempty(setdiff(public_names, docs_names))
end

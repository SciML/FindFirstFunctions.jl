using SciMLTesting, FindFirstFunctions, JET, Test

run_qa(
    FindFirstFunctions;
    api_docs_kwargs = (; rendered = true),
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

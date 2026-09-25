using SciMLTesting, FindFirstFunctions, JET, Test

run_qa(
    FindFirstFunctions;
    # Custom LLVM IR has no public Julia entry point; Base.llvmcall is the compiler
    # intrinsic required by the package's SIMD kernels.
    ei_kwargs = (; all_qualified_accesses_are_public = (; ignore = (:llvmcall,))),
)

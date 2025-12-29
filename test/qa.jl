using FindFirstFunctions, Aqua, ExplicitImports
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

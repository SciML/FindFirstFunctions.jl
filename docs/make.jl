using Documenter, FindFirstFunctions

cp(joinpath(@__DIR__, "Manifest.toml"), joinpath(@__DIR__, "src/assets/Manifest.toml"), force = true)
cp(joinpath(@__DIR__, "Project.toml"), joinpath(@__DIR__, "src/assets/Project.toml"), force = true)

ENV["GKSwstype"] = "100"

makedocs(
    modules = [FindFirstFunctions],
    sitename = "FindFirstFunctions.jl",
    clean = true,
    doctest = false,
    linkcheck = true,
    format = Documenter.HTML(
        assets = ["assets/favicon.ico"],
        canonical = "https://docs.sciml.ai/FindFirstFunctions/stable/"
    ),
    pages = ["index.md"]
)

deploydocs(repo = "github.com/SciML/FindFirstFunctions.jl"; push_preview = true)

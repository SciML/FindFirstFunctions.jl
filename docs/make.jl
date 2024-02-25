using Documenter, FindFirstFunctions

cp("./docs/Manifest.toml", "./docs/src/assets/Manifest.toml", force = true)
cp("./docs/Project.toml", "./docs/src/assets/Project.toml", force = true)

ENV["GKSwstype"] = "100"

makedocs(
    modules = [FindFirstFunctions],
    sitename = "FindFirstFunctions.jl",
    clean = true,
    doctest = false,
    linkcheck = true,
    warnonly = [:missing_docs],
    format = Documenter.HTML(
        assets = ["assets/favicon.ico"],
        canonical = "https://docs.sciml.ai/FindFirstFunctions/stable/",
    ),
    pages = ["index.md"],
)

deploydocs(repo = "github.com/SciML/FindFirstFunctions.jl"; push_preview = true)

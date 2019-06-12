using Pkg
Pkg.activate(".")


using Documenter, RPH

makedocs(
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"      # Solve url problem on laptop
    ),
    sitename="RPH",
    pages = [
        "Home" => "index.md",
        "Tutorial" => "problem_example.md",
    ],
    modules = [RPH]
)
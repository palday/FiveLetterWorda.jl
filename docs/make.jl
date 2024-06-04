using Documenter
using FiveLetterWorda

makedocs(; modules=[FiveLetterWorda],
         authors="Phillip Alday",
         repo="https://github.com/palday/FiveLetterWorda.jl/blob/{commit}{path}#{line}",
         sitename="FiveLetterWorda.jl",
         format=Documenter.HTML(; prettyurls=get(ENV, "CI", "false") == "true",
                                repolink="https://github.com/palday/FiveLetterWorda.jl",
                                canonical="https://palday.github.io/FiveLetterWorda.jl/stable",
                                assets=String[]),
         warnonly=[:cross_references],
         pages=["Home" => "index.md",
                "API" => "api.md"])

deploydocs(; repo="github.com/palday/FiveLetterWorda.jl",
           devbranch="main",
           push_preview=true)

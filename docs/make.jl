using Documenter, JSON3, StructTypes

makedocs(;
    modules=[JSON3],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/quinnj/JSON3.jl/blob/{commit}{path}#L{line}",
    sitename="JSON3.jl",
    authors="Jacob Quinn",
    strict=true,
)

deploydocs(;
    repo="github.com/quinnj/JSON3.jl",
    devbranch = "main",
)

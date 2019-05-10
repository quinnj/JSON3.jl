using Test, JSON3, Dates

# builtins
# Any
@test JSON3.read("") == NamedTuple()
@test JSON3.read("{\"hey\":1}") == (hey=1,)
@test JSON3.read("[\"hey\",1]") == ["hey",1]
@test JSON3.read("1.0") === 1
@test JSON3.read("1") === 1
@test JSON3.read("1.1") === 1.1
@test JSON3.read("+1.1") === 1.1
@test JSON3.read("-1.1") === -1.1
@test JSON3.read("\"hey\"") == "hey"
@test JSON3.read("null") === nothing
@test JSON3.read("true") === true
@test JSON3.read("false") === false

# Union
@test JSON3.read("1.0", Union{Float64, Int}) === 1.0
@test JSON3.read("1.1", Union{Float64, Int}) === 1.1
@test JSON3.read("1.1", Union{Float64, String}) === 1.1
@test JSON3.read("\"1.1\"", Union{Float64, String}) === "1.1"
@test JSON3.read("1.1", Union{Nothing, Float64}) === 1.1
@test JSON3.read("null", Union{Nothing, Float64}) === nothing

# Enum
@enum FRUIT apple orange banana
@test JSON3.read(JSON3.write(apple), FRUIT) === apple

# NamedTuple
@test JSON3.read("{\"hey\":1}", NamedTuple) == (hey=1,)
@test JSON3.read("{\"hey\":1,\"ho\":2}", NamedTuple) == (hey=1,ho=2)

@test JSON3.write(Dict("name"=>1)) == "{\"name\":1}"
@test JSON3.read(JSON3.write(Dict("name"=>1)), Dict) == Dict("name"=>1)
@test JSON3.write(Dict()) == "{}"
@test JSON3.read(JSON3.write(Dict()), Dict) == Dict()

@test JSON3.write([]) == "[]"
@test JSON3.read(JSON3.write([]), Array) == []
@test JSON3.write([1, 2, 3]) == "[1,2,3]"
@test JSON3.read(JSON3.write([1, 2, 3]), Array) == [1, 2, 3]
@test JSON3.write(["hey", "there", "sailor"]) == "[\"hey\",\"there\",\"sailor\"]"
@test JSON3.read(JSON3.write(["hey", "there", "sailor"]), Array) == ["hey", "there", "sailor"]
@test JSON3.write([1, 2, 3, "hey", "there", "sailor"]) == "[1,2,3,\"hey\",\"there\",\"sailor\"]"
@test JSON3.read(JSON3.write([1, 2, 3, "hey", "there", "sailor"]), Array) == [1, 2, 3, "hey", "there", "sailor"]
@test JSON3.write([split("hey there sailor", ' ')...]) == "[\"hey\",\"there\",\"sailor\"]"
@test JSON3.read(JSON3.write([split("hey there sailor", ' ')...]), Array) == [split("hey there sailor", ' ')...]

@test JSON3.write(()) == "[]"
@test JSON3.read(JSON3.write(()), Tuple) == ()
@test JSON3.write((1, 2, 3)) == "[1,2,3]"
@test JSON3.read(JSON3.write((1, 2, 3)), Tuple) == (1, 2, 3)

@test JSON3.read(JSON3.write((1, 2, 3)), Set) == Set([1, 2, 3])

@test JSON3.write(1) == "1"
@test JSON3.read(JSON3.write(1), Int) == 1
for i in rand(Int, 1000000) # takes about 0.8 seconds
    @test JSON3.read(JSON3.write(i), Int) == i
end
@test JSON3.write(1.0) == "1.0"
@test JSON3.read(JSON3.write(1.0), Float64) == 1.0

include("floatparsing.jl")

@test JSON3.write("") == "\"\""
@test JSON3.read(JSON3.write(""), String) == ""
@test JSON3.write("hey") == "\"hey\""
@test JSON3.read(JSON3.write("hey"), String) == "hey"
let tmp = tempname()
    open(tmp, "w") do f
        write(f, "\"hey\"")
    end
    io = open(tmp)
    @test JSON3.read(io, String) == "hey"
    close(io)
    rm(tmp)
end
@test JSON3.read(JSON3.write('h'), Char) == 'h'
@test JSON3.write(Symbol()) == "\"\""
@test JSON3.read(JSON3.write(Symbol()), Symbol) == Symbol()
@test JSON3.write(:hey) == "\"hey\""
@test JSON3.read(JSON3.write(:hey), Symbol) == :hey

@test JSON3.write(Date(2017, 1, 1)) == "\"2017-01-01\""
@test JSON3.read(JSON3.write(Date(2017, 1, 1)), Date) == Date(2017, 1, 1)
df = dateformat"mm/dd/yyyy"
@test JSON3.write(Date(2017, 1, 1); dateformat=df) == "\"01/01/2017\""
@test JSON3.read(JSON3.write(Date(2017, 1, 1); dateformat=df), Date; dateformat=df) == Date(2017, 1, 1)

@test JSON3.write(nothing) == "null"
@test JSON3.read(JSON3.write(nothing), Nothing) === nothing

@test JSON3.write(missing) == "null"
@test JSON3.read(JSON3.write(missing), Missing) === missing

@test JSON3.write(true) == "true"
@test JSON3.read(JSON3.write(true), Bool) == true
@test JSON3.write(false) == "false"
@test JSON3.read(JSON3.write(false), Bool) == false

@test JSON3.read("function (data) {}") == JSON3.Function("function (data) {}")
@test JSON3.read("function (data) {}", JSON3.Function) == JSON3.Function("function (data) {}")
@test JSON3.read(JSON3.write(JSON3.Function("function (data) {}"))) == JSON3.Function("function (data) {}")

mutable struct A
    int8::Int8
    int::Int
    float::Float64
    str::String
    nullint::Union{Nothing, Int}
    nullnullint::Union{Nothing, Int}
    nullstr::Union{Nothing, String}
    nullnullstr::Union{Nothing, String}
    void::Nothing
    truebool::Bool
    falsebool::Bool
    b::B

    ints::Vector{Int}
    emptyarray::Vector{Int}
    bs::Vector{B}
    dict::Dict{String,Int}
    emptydict::Dict{String,Int}
end

a = A(0, -1, 3.14, "string \\\" w/ escaped double quote", 4, nothing,
        "null string", nothing, nothing, true, false, b1, [1,2,3], Int[], [b2, b3],
        Dict("1"=>1, "2"=>2), Dict{String,Int}())

json = JSON3.write(a)
a2 = JSON3.read(json, A)

str = "{\n          \"int8\": 0,\n           \"int\": -1,\n         \"float\": 3.14,\n           \"str\": \"string \\\\\\\" w/ escaped double quote\",\n       \"nullint\": 4,\n   \"nullnullint\": null,\n       \"nullstr\": \"null string\",\n   \"nullnullstr\": null,\n          \"void\": null,\n      \"truebool\": true,\n     \"falsebool\": false,\n             \"b\": {\n                       \"id\": 1,\n                     \"name\": \"harry\"\n                  },\n          \"ints\": [\n                    1,\n                    2,\n                    3\n                  ],\n    \"emptyarray\": [],\n            \"bs\": [\n                    {\n                         \"id\": 2,\n                       \"name\": \"hermione\"\n                    },\n                    {\n                         \"id\": 3,\n                       \"name\": \"ron\"\n                    }\n                  ],\n          \"dict\": {\n                     \"1\": 1,\n                     \"2\": 2\n                  },\n     \"emptydict\": {}\n}"
io = IOBuffer()
JSON3.pretty(io, json)
@test String(take!(io)) == str

# 230
@test a.int8 == a2.int8
@test a.int == a2.int
@test a.float == a2.float
@test a.str == a2.str
@test a.nullint == a2.nullint
@test a.nullnullint === nothing && a2.nullnullint === nothing
@test a.nullstr == a2.nullstr
@test a.nullnullstr === nothing && a2.nullnullstr === nothing
@test a.void == a2.void
@test a.truebool == a2.truebool
@test a.falsebool == a2.falsebool
@test a.b == a2.b
@test a.ints == a2.ints
@test a.emptyarray == a2.emptyarray
@test a.bs == a2.bs
@test a.dict == a2.dict
@test a.emptydict == a2.emptydict

# test invalid handling
@test_throws ArgumentError JSON3.read("trua")
@test_throws ArgumentError JSON3.read("tru")
@test_throws ArgumentError JSON3.read("fals")
@test_throws ArgumentError JSON3.read("falst")
@test_throws ArgumentError JSON3.read("f")
@test_throws ArgumentError JSON3.read("a", Bool)

@test_throws ArgumentError JSON3.read("nul", Nothing)
@test_throws ArgumentError JSON3.read("nule", Nothing)
@test_throws ArgumentError JSON3.read("abcd", Nothing)

@test_throws ArgumentError JSON3.read("nule", Union{Nothing, Int})
@test_throws Parsers.Error JSON3.read("abc", Union{Nothing, Int})

@test_throws Parsers.Error JSON3.read("abc", Int)

@test_throws ArgumentError JSON3.read("a", Char)
@test_throws ArgumentError JSON3.read("\"abc\"", Char)

@test JSON3.read(IOBuffer("\"\\u003e\\u003d\$1B\""), String) == ">=\$1B"

# Default DateTime format
@test JSON3.read("\"2019-03-25T23:12:51.191\"", DateTime) == DateTime(2019, 3, 25, 23, 12, 51, 191)

# Unions which both read strings
@test JSON3.read("\"foo\"", Union{DateTime, String}) == "foo"

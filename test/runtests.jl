using Test, JSON3

@enum Fruit apple banana

struct XInt
    x::Int64
end

struct A
    a::Int
    b::Int
    c::Int
    d::Int
end

mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
    B() = new()
end

struct C
end

abstract type Vehicle end

struct Car <: Vehicle
    type::String
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    type::String
    make::String
    model::String
    payloadCapacity::Float64
end

abstract type Expression end

abstract type Literal <: Expression end

abstract type BinaryFunction <: Expression end

struct LiteralValue <: Literal
    exprType::String
    value::Any
end

struct AndFunction <: BinaryFunction
    exprType::String
    lhs::Expression
    rhs::Expression
end

@testset "JSON3" begin

@testset "read.jl" begin

@test_throws ArgumentError JSON3.read("")
@test JSON3.read("{\"hey\":1}").hey == 1
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

@test_throws ArgumentError JSON3.read("{")
@test JSON3.read("{}") == JSON3.Object()
@test_throws ArgumentError JSON3.read("{a")
@test JSON3.read("{\"a\": 1}").a == 1
@test JSON3.read("{\"\\\"hey\\\"\": 1}")["\"hey\""] == 1
@test_throws ArgumentError JSON3.read("{\"a\"}")
@test JSON3.read("{\"a\": {\"a\": {\"a\": 1}}}").a.a.a == 1
@test JSON3.read("[3.14, 1]") == [3.14, 1]
@test JSON3.read("[1, 3.14]") == [1, 3.14]
@test JSON3.read("[null, 1]") == [nothing, 1]
@test JSON3.read("[1, null]") == [1, nothing]
@test JSON3.read("[null, null]") == [nothing, nothing]
@test JSON3.read("[null, \"hey\"]") == [nothing, "hey"]
@test_throws ArgumentError JSON3.read("{\"a\": 1\"")
@test_throws ArgumentError JSON3.read("{\"a\": 1, a")
@test JSON3.read("[]") == []
@test JSON3.read("[1]") == [1]
@test JSON3.read("[1,2,3]") == [1,2,3]
@test_throws ArgumentError JSON3.read("[1 a")
@test_throws ArgumentError JSON3.read("nulL")
@test_throws ArgumentError JSON3.read("\"\b\"")

obj = JSON3.read("""
{
    "int": 1,
    "float": 2.1,
    "bool1": true,
    "bool2": false,
    "none": null,
    "str": "\\"hey there sailor\\"",
    "obj": {
                "a": 1,
                "b": null,
                "c": [null, 1, "hey"],
                "d": [1.2, 3.4, 5.6]
            },
    "arr": [null, 1, "hey"],
    "arr2": [1.2, 3.4, 5.6]
}
""")
@test obj.int === Int64(1)
@test obj.float === 2.1
@test obj.bool1 === true
@test obj.bool2 === false
@test obj.none === nothing
@test obj.str == "\"hey there sailor\""
@test obj.obj.a === Int64(1)
@test obj.obj.b === nothing
@test obj.obj.c == [nothing, 1, "hey"]
@test obj.obj.d == [1.2, 3.4, 5.6]
@test obj.arr == [nothing, 1, "hey"]
@test obj.arr2 == [1.2, 3.4, 5.6]

@test_throws ArgumentError JSON3.read("trua")
@test_throws ArgumentError JSON3.read("tru")
@test_throws ArgumentError JSON3.read("fals")
@test_throws ArgumentError JSON3.read("falst")
@test_throws ArgumentError JSON3.read("f")

@test JSON3.read("\"\\u003e\\u003d\$1B\"") == ">=\$1B"

obj = JSON3.read("""
{ "a": 1,
  "b": 2,
  "c": 3,
  "d": 4
}""")

@test length(obj) == 4
for (i, (k, v)) in enumerate(obj)
    @test i == v
end

@test get(obj, :a) == 1
@test_throws KeyError get(obj, :e)
@test get(obj, :a, 2) == 1
@test get(obj, :e, 5) == 5
@test get(()->5, obj, :e) == 5
@test propertynames(obj) == [:a, :b, :c, :d]
@test obj["a"] == 1

arr = JSON3.read("""
[ 1,
  2,
  3,
  4
]""")

@test length(arr) == 4
@test size(arr) == (4,)

for (i, v) in enumerate(arr)
    @test i == v
end

@test arr[1] == 1
@test arr[end] == 4

arr = JSON3.read(SubString("""
[ 1,
  2,
  3,
  4
]""", 1, 20))

@test length(arr) == 4
@test size(arr) == (4,)

for (i, v) in enumerate(arr)
    @test i == v
end

@test arr[1] == 1
@test arr[end] == 4

end # @testset "read.jl"

@testset "structs.jl" begin

arr = JSON3.read(SubString("""
[ 1,
  2,
  3,
  4
]""", 1, 20), Vector{Int})

@test length(arr) == 4
@test size(arr) == (4,)

for (i, v) in enumerate(arr)
    @test i == v
end

@test arr[1] == 1
@test arr[end] == 4

@test JSON3.write(arr) == "[1,2,3,4]"

x = JSON3.read("1", Union{Int, Missing})
@test x == 1

x = JSON3.read("null", Union{Int, Missing})
@test x === missing

x = JSON3.read("1", Union{Int, Float64})
@test x === 1.0

JSON3.construct(::Type{JSON3.PointerString}, ptr::Ptr{UInt8}, len::Int) = JSON3.PointerString(ptr, len)
x = JSON3.read("\"hey\"", JSON3.PointerString);
@test x == "hey"
@test typeof(x) == JSON3.PointerString
@test JSON3.write(x) == "\"hey\""

@test JSON3.read("\"apple\"", Fruit) == apple
@test_throws Union{UndefVarError, ArgumentError} JSON3.read("\"watermelon\"", Fruit)
@test JSON3.write(apple) == "\"apple\""

@test JSON3.read("\"apple\"", Symbol) == :apple
@test JSON3.write(:apple) == "\"apple\""

@test JSON3.read("true", Bool)
@test JSON3.read("false", Bool) === false
@test JSON3.write(true) == "true"
@test JSON3.write(false) == "false"

JSON3.StructType(::Type{XInt}) = JSON3.NumberType()
JSON3.numbertype(::Type{XInt}) = Int64
Base.Int64(x::XInt) = x.x
x = XInt(10)
@test JSON3.read("10", XInt) == x
@test JSON3.write(x) == "10"

@test JSON3.read("[1,2,3]", Array) == Any[1,2,3]
@test JSON3.write(Any[1,2,3]) == "[1,2,3]"
@test JSON3.read("[1,2,3]", Tuple) == (1,2,3)
@test JSON3.write((1,2,3)) == "[1,2,3]"
@test JSON3.read("[1,2,3]", Set) == Set([1,2,3])
@test JSON3.write(Set([1,2])) in ("[1,2]", "[2,1]")

@test JSON3.read("{\"a\": 1, \"b\": 2}", Dict) == Dict("a"=>1, "b"=>2)
@test JSON3.write(Dict("a"=>1, "b"=>2)) in ("{\"a\":1,\"b\":2}", "{\"b\":2,\"a\":1}")
@test JSON3.read("{\"a\": 1, \"b\": 2}", Dict{String, Any}) == Dict("a"=>1, "b"=>2)
@test JSON3.read("{\"a\": 1, \"b\": 2}", Dict{Symbol, Int}) == Dict(:a=>1, :b=>2)
@test JSON3.write(Dict(:a=>1, :b=>2)) in ("{\"a\":1,\"b\":2}", "{\"b\":2,\"a\":1}")
@test JSON3.read("{\"a\": 1, \"b\": 2}", NamedTuple) == (a=1, b=2)
@test JSON3.write((a=1, b=2)) == "{\"a\":1,\"b\":2}"
@test JSON3.read("{\"a\": 1, \"b\": 2}", NamedTuple{(:a, :b)}) == (a=1, b=2)
@test JSON3.read("{\"a\": 1, \"b\": 2}", NamedTuple{(:a,)}) == (a=1,)
@test JSON3.write((a=1,)) == "{\"a\":1}"
@test JSON3.read("{\"a\": 1, \"b\": 2}", NamedTuple{(:a, :b), Tuple{Int, Int}}) == (a=1, b=2)
@test JSON3.read("{\"a\": 1, \"b\": 2}", NamedTuple{(:a, :b), Tuple{Float64, Float64}}) == (a=1.0, b=2.0)
@test JSON3.write((a=1.0, b=2.0)) == "{\"a\":1.0,\"b\":2.0}"

obj = JSON3.read("""
{ "a": 1,
  "b": 2,
  "c": 3,
  "d": 4
}
""", A)

@test obj.a == 1
@test obj.d == 4

@test_throws ArgumentError JSON3.read("", A)
@test_throws ArgumentError JSON3.read("a", A)
@test_throws ArgumentError JSON3.read("{a", A)
@test_throws ArgumentError JSON3.read("{\"a\"a", A)
@test_throws ArgumentError JSON3.read("{\"a\": 1a", A)
@test_throws ArgumentError JSON3.read("{\"a\": 1, a", A)

@test JSON3.read("{}", C) == C()
@test JSON3.write(obj) == "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}"

@test JSON3.read("1", Union{String, Int}) == 1
@test JSON3.read("\"1\"", Union{String, Int}) == "1"
@test JSON3.read("null", Union{Int, String, Nothing}) === nothing
@test JSON3.read("1.0", Union{Float64, Int}) === 1.0

@test JSON3.read("1", Any) == 1
@test JSON3.read("3.14", Any) == 3.14
@test JSON3.read("\"a\"", Any) == "a"
@test JSON3.read("true", Any) === true
@test JSON3.read("false", Any) === false
@test JSON3.read("null", Any) === nothing
@test JSON3.read("[1,2,3]", Any) == [1,2,3]
@test JSON3.read("\"a\"", String) == "a"
@test JSON3.read("1", Int64) === Int64(1)
@test JSON3.read("3.14", Float64) === 3.14
@test JSON3.read("true", Bool) === true
@test JSON3.read("false", Bool) === false
@test JSON3.read("null", Nothing) === nothing
@test JSON3.read("null", Missing) === missing
@test JSON3.read("\"a\"", Char) == 'a'
@test JSON3.read("{\"a\": 1}", Any)["a"] == 1
@test JSON3.read("{\"a\": 1}", Dict{Symbol, Any})[:a] == 1
@test JSON3.read("[1,2,3]", Base.Array{Any}) == [1,2,3]
@test JSON3.read("[]", Vector{Any}) == []
@test JSON3.read("{}", Dict{Symbol, Any}) == Dict{Symbol, Any}()

@test_throws ArgumentError JSON3.read("hey", Any)
@test_throws ArgumentError JSON3.read("hey", String)
@test_throws ArgumentError JSON3.read("\"hey", String)
@test_throws ArgumentError JSON3.read("\"hey\\", String)
@test_throws ArgumentError JSON3.read("\"hey\\\\", String)
@test_throws ArgumentError JSON3.read("\"a", Char)
@test_throws ArgumentError JSON3.read("\"ab\"", Char)
@test_throws ArgumentError JSON3.read("trua", Bool)
@test_throws ArgumentError JSON3.read("tru", Bool)
@test_throws ArgumentError JSON3.read("fals", Bool)
@test_throws ArgumentError JSON3.read("falst", Bool)
@test_throws ArgumentError JSON3.read("f", Bool)
@test_throws ArgumentError JSON3.read("a1bc", Int)
@test_throws ArgumentError JSON3.read("a1.0b", Float64)
@test_throws ArgumentError JSON3.read("a1bc", Vector{Any})
@test_throws ArgumentError JSON3.read("[1,2n", Vector{Any})
@test_throws ArgumentError JSON3.read("a1bc", Dict{Symbol, Any})
@test_throws ArgumentError JSON3.read("{a1bc", Dict{Symbol, Any})
@test_throws ArgumentError JSON3.read("{\"a\"1bc", Dict{Symbol, Any})
@test_throws ArgumentError JSON3.read("{\"a\": 1bc", Dict{Symbol, Any})
@test_throws ArgumentError JSON3.read("{\"a\": 1, bc", Dict{Symbol, Any})

JSON3.StructType(::Type{B}) = JSON3.Mutable()

b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "a": 1,
    "c": 3
}""", B)

@test b.a == 1
@test b.b == 2
@test b.c == 3
@test b.d == 4

@test_throws ArgumentError JSON3.read("a", B)
@test_throws ArgumentError JSON3.read("{a", B)
@test_throws ArgumentError JSON3.read("{\"a\": 1b", B)
@test_throws ArgumentError JSON3.read("{\"a\": 1, b", B)
b = JSON3.read("{}", B)
@test typeof(b) == B

b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "a": 1,
    "c": 3,
    "e": 5
}""", B)

@test b.a == 1
@test JSON3.write(b) == "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}"

JSON3.names(::Type{B}) = ((:a, :z),)
b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "z": 1,
    "c": 3,
    "e": 5
}""", B)

@test b.a == 1
@test JSON3.write(b) == "{\"z\":1,\"b\":2,\"c\":3,\"d\":4}"

JSON3.excludes(::Type{B}) = (:c, :d)
b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "z": 1,
    "c": 3,
    "e": 5
}""", B)
@test JSON3.write(b) == "{\"z\":1,\"b\":2}"

JSON3.StructType(::Type{Vehicle}) = JSON3.AbstractType()
JSON3.subtypes(::Type{Vehicle}) = (car=Car, truck=Truck)

car = JSON3.read("""
{
    "type": "car",
    "make": "Mercedes-Benz",
    "model": "S500",
    "seatingCapacity": 5,
    "topSpeed": 250.1
}""", Vehicle)

@test typeof(car) == Car
@test car.make == "Mercedes-Benz"
@test car.topSpeed === 250.1
@test JSON3.write(car) == "{\"type\":\"car\",\"make\":\"Mercedes-Benz\",\"model\":\"S500\",\"seatingCapacity\":5,\"topSpeed\":250.1}"

truck = JSON3.read("""
{
    "type": "truck",
    "make": "Isuzu",
    "model": "NQR",
    "payloadCapacity": 7500.5
}""", Vehicle)

@test typeof(truck) == Truck
@test truck.make == "Isuzu"
@test truck.payloadCapacity == 7500.5
@test JSON3.write(truck) == "{\"type\":\"truck\",\"make\":\"Isuzu\",\"model\":\"NQR\",\"payloadCapacity\":7500.5}"

@test_throws ArgumentError JSON3.read("", Vehicle)
@test_throws ArgumentError JSON3.read("a", Vehicle)
@test_throws ArgumentError JSON3.read("{a", Vehicle)
@test_throws ArgumentError JSON3.read("{}", Vehicle)
@test_throws ArgumentError JSON3.read("{\"a\"a", Vehicle)
@test_throws ArgumentError JSON3.read("{\"a\": 1a", Vehicle)
@test_throws ArgumentError JSON3.read("{\"a\": 1, a", Vehicle)
@test_throws ArgumentError JSON3.read("{\"a\": 1}", Vehicle)

JSON3.StructType(::Type{Expression}) = JSON3.AbstractType()
JSON3.subtypes(::Type{Expression}) = (AND=AndFunction, LITERAL=LiteralValue)
JSON3.subtypekey(::Type{Expression}) = :exprType

expr = JSON3.read("""
{
    "exprType": "AND",
    "lhs": {
        "exprType": "LITERAL",
        "value": 3.14
    },
    "rhs": {
        "exprType": "AND",
        "lhs": {
            "exprType": "LITERAL",
            "value": null
        },
        "rhs": {
            "exprType": "LITERAL",
            "value": "hey"
        }
    }
}
""", Expression)
@test expr.exprType == "AND"
@test JSON3.write(expr) == "{\"exprType\":\"AND\",\"lhs\":{\"exprType\":\"LITERAL\",\"value\":3.14},\"rhs\":{\"exprType\":\"AND\",\"lhs\":{\"exprType\":\"LITERAL\",\"value\":null},\"rhs\":{\"exprType\":\"LITERAL\",\"value\":\"hey\"}}}"

@test JSON3.write(Int64) == "\"Int64\""
@test JSON3.write(Float64) == "\"Float64\""
@test JSON3.write(String) == "\"String\""
@test JSON3.write(Vector{Int64}) == "\"Array{Int64,1}\""
@test JSON3.write(NamedTuple{(:a, :b), Tuple{Int64, String}}) == "\"NamedTuple{(:a, :b),Tuple{Int64,String}}\""
@test JSON3.write(Dict{Symbol, Any}) == "\"Dict{Symbol,Any}\""
@test JSON3.write(Bool) == "\"Bool\""
@test JSON3.write(Nothing) == "\"Nothing\""
@test JSON3.write(Missing) == "\"Missing\""
@test JSON3.write(A) == "\"A\""
@test JSON3.write(B) == "\"B\""
@test JSON3.write(Vehicle) == "\"Vehicle\""

end # @testset "structs.jl"

include("json.jl")

# more tests for coverage
obj = JSON3.read("{\"hey\":1}")
@test get(obj, Int, :hey) == 1
@test get(obj, Int, :ho, 2) == 2

@test JSON3.read("{\"hey\":1}") == JSON3.read(b"{\"hey\":1}") == JSON3.read(IOBuffer("{\"hey\":1}"))

arr = JSON3.read("[\"hey\",1, null, false, \"ho\", {\"a\": 1}, 2]")
@test Base.IndexStyle(arr) == Base.IndexLinear()
@test arr[7] == 2

str = "hey"
ptr = JSON3.PointerString(pointer(str), 3)
@test hash(str) == hash(ptr)
@test codeunit(ptr) == UInt8
@test JSON3.names(1) == ()
@test JSON3.names(Any) == ()
@test JSON3.excludes(1) == ()
@test JSON3.excludes(Any) == ()
@test JSON3.omitempties(1) == ()
@test JSON3.omitempties(Any) == ()

@test JSON3.subtypekey(1) == :type
@test JSON3.subtypekey(Any) == :type
@test JSON3.subtypes(1) == NamedTuple()
@test JSON3.subtypes(Any) == NamedTuple()

@test JSON3.read(b"\"a\"", String) == "a"
@test JSON3.read(IOBuffer("\"a\""), String) == "a"
@test JSON3.StructType(Char) == JSON3.StringType()
@test JSON3.construct(String, "hey") == "hey"
@test JSON3.StructType(Bool) == JSON3.BoolType()
@test JSON3.construct(Bool, true) === true
@test JSON3.StructType(UInt8) == JSON3.NumberType()
@test JSON3.numbertype(UInt8) == UInt8
@test JSON3.numbertype(1) == Float64
@test JSON3.construct(String, "hey") == "hey"
@test JSON3.StructType(typeof((1,2))) == JSON3.ArrayType()
x = Dict(:hey=>1)
@test JSON3.construct(Dict{Symbol, Any}, x) == x

@test JSON3.gettapelen(Int64) == 2
@test JSON3.regularstride(Missing) == false
@test JSON3.regularstride(Int64) == true
@test JSON3.regularstride(Union{Int64, Float64}) == true
@test JSON3.getvalue(Nothing, [], [], 1, 2) === nothing
@test JSON3.defaultminimum(nothing) == 4
@test JSON3.defaultminimum(Int64) == 16
@test JSON3.defaultminimum('1') == 3

@test JSON3._isempty(B(), 1) === false
@test !JSON3._isempty((a=1, c=2))
@test JSON3._isempty(1) === false
@test JSON3._isempty(nothing) === true
@test JSON3._isempty("ho") === false

end # @testset "JSON3"

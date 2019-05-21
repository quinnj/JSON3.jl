using Test, JSON3, Dates

@testset "JSON3" begin

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

struct A
    a::Int
    b::Int
    c::Int
    d::Int
end

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
@test JSON3.read("{\"a\": 1}", Any).a == 1
@test JSON3.read("{\"a\": 1}", NamedTuple).a == 1
@test JSON3.read("[1,2,3]", Base.Array{Any}) == [1,2,3]

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

mutable struct B
    a::Int
    b::Int
    c::Int
    d::Int
    B() = new()
end

JSON3.StructType(::Type{B}) = JSON3.MutableSetField()

b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "a": 1,
    "c": 3
}""")

@test b.a == 1
@test b.b == 2
@test b.c == 3
@test b.d == 4

b = JSON3.read("""
{
    "d": 4,
    "b": 2,
    "a": 1,
    "c": 3,
    "e": 5
}""")

@test b.a == 1

abstract type Vehicle end

struct Car <: Vehicle
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    make::String
    model::String
    payloadCapacity::Float64
end

JSON3.StructType(::Type{Vehicle}) = JSON3.AbstractType()
JSON3.subtypes(::Type{Vehicle}) = Dict("car"=>Car, "truck"=>Truck)

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

end # @testset

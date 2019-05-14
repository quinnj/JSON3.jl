using Test, JSON3, Dates

# builtins
@test JSON3.read("") == JSON3.Object()
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


using JSON3, BenchmarkTools

str = """
{
    "a": 1,
    "b" :2.1,
    "c": 
    "3",
    "d": [1,2,3,5,8],
    "e": [
        1,"23",
        [4,5]],
    "f": {
        "a": ["2"],
        "b": 1
    }
}
"""

reader = JSON3.Reader()
obj = JSON3.parse!(reader, str, JSON3.JSONObject)

function f0(str)
    x = JSON3.read(str)
    x["f"]["b"]
end

function f1(reader, str)
    obj = JSON3.parse!(reader, str, JSON3.JSONObject)
    obj["f", JSON3.JSONObject]["b", Int64]
end

function f2(obj)
    obj["f", JSON3.JSONObject]["b", Int64]
end

@benchmark f0($str)
@benchmark f1($reader, $str)
@benchmark f2($obj)

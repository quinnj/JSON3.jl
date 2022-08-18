using JSON3: JSONObject, JSONArray, JSONField, JSONItem, key, value, Reader, parse!, next, getpair

@testset "JSONReader" begin
    @testset "JSONReader: vector INT" begin
        str = """
        {
            "a": [1,2,3,5,8]
        }
        """
    
        reader = Reader()
        obj = parse!(reader, str, JSONObject)
    
        field = first(obj)
        @test field isa JSONField
        @test key(field) == "a"
        @test value(field) isa JSONItem
        @test value(field, JSONArray) isa JSONArray
    
        v = obj["a"]
        @test v isa JSONItem
    
        v = obj["a", JSONArray]
        @test first(v) isa JSONItem
        @test eltype(v) == JSONItem
        @test [JSON3.as(x, Int64) for x in v] == [1,2,3,5,8]
    
        v = obj["a", JSONArray{Int64}]
        @test collect(v) == [1,2,3,5,8]
        @test eltype(v) == Int64
    end
    
    @testset "JSONReader: vector INT|FLOAT" begin
        str = """
        {
            "a": [1.0,2.5]
        }
        """
    
        reader = Reader()
        obj = parse!(reader, str, JSONObject)
    
        v = obj["a", JSONArray{Float64}]
        @test collect(v) == [1.0, 2.5]
    end
    
    @testset "JSONReader: Object" begin
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
    
        reader = Reader()
        obj_ = parse!(reader, str)
        @test obj_ isa JSONItem
        obj = parse!(reader, str, JSONObject)
        @test obj isa JSONObject
        @test JSON3.as(obj_, JSONObject) == obj

        @test [key(field) for field in obj] == ["a", "b", "c", "d", "e", "f"]

        cursor1 = next(obj)
        field = getpair(obj, cursor1)
        k, v1, v2  = key(field), value(field, Int), value(field, Float64)
        v3 = obj["a", Int]
        v4 = obj["a", Float64]
        @test k == "a"
        @test_throws AssertionError value(field, JSONArray)
        @test (v1, v2, v3, v4) == (1,1,1.0,1.0)
    
        cursor2 = next(obj, cursor1) # cursor on the field
        field = getpair(obj, cursor2)
        @test field isa JSONField
        @test key(field) == "b"
        v1 = value(field, Float64)

        cursor2_value = JSON3.findcursor(obj, "b") # cursor on the value
        @test_throws KeyError JSON3.findcursor(obj, "b_")
        @test JSON3.tryfindcursor(obj, "b_", nothing) === nothing        
        v2 = obj[cursor2_value, Float64]
        @test (v1, v2) == (2.1, 2.1)
    
        @test  obj["c", AbstractString] == "3"
            
        v = obj["d", JSONArray{Int64}]
        @test collect(v) == [1,2,3,5,8]

        v = obj["e", JSONArray]
        @test v == obj["e", JSONArray{Any}]
        @test length(v) == 3
        vs = collect(v)
        @test JSON3.as(vs[1], Int64) == 1
        @test JSON3.as(vs[2], AbstractString) == "23"
        @test JSON3.as(vs[3], JSONArray{Int64}) |> collect == [4,5]
    
        v = obj["f", JSONObject]
        @test length(v) == 2
        @test collect(v["a", JSONArray{AbstractString}]) == ["2"]
        @test v["b", Int64] == 1
    end
end

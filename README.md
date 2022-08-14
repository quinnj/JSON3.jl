
# JSON3.jl

[![Build Status](https://travis-ci.com/quinnj/JSON3.jl.svg?branch=master)](https://travis-ci.com/quinnj/JSON3.jl)
[![codecov](https://codecov.io/gh/quinnj/JSON3.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/quinnj/JSON3.jl)

### Documentation

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://quinnj.github.io/JSON3.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://quinnj.github.io/JSON3.jl/dev)

*Yet another JSON package for Julia; this one is for speed and slick struct mapping*

### TL;DR

#### Basic

```julia
# builtin reading/writing
JSON3.read(json_string)
JSON3.write(x)

# custom types
JSON3.read(json_string, T; kw...)
JSON3.write(x)
```

#### More complicated

```julia
# custom types: incrementally update a mutable struct
x = T()
JSON3.read!(json_string, x; kw...)
JSON3.write(x)

# read from file
json_string = read("my.json", String)
JSON3.read(json_string)
JSON3.read(json_string, T; kw...)

# write to file
open("my.json", "w") do f
    JSON3.write(f, x)
    println(f)
end

# write a pretty file
open("my.json", "w") do f
    JSON3.pretty(f, JSON3.write(x))
    println(f)
end

# generate a type from json
using StructTypes
JSON3.@generatetypes json_string_sample
JSON3.read(json_string, JSONTypes.Root)
```

#### Non-allocating interface

```julia
json_string = """
{
    "a": 1,
    "b": [1,2,3,5,8],
    "c": {
        "a": ["2"],
    }
}
"""
reader = JSON3.Reader()
obj = JSON3.parse!(reader, json_string, JSON3.JSONObject) # returns a JSON3.JSONObject

# method 1
obj["a", Int64] # 1
# method 2
cursor = findcursor(obj, "a") # JSON3.Cursor
item = obj[cursor, Int64] # 1
# method 3
field = first(obj)
key(field) # "a", SubString
value(field, Int64) # 1

# Array
collect(obj["b", JSON3.JSONArray{Int64}]) # [1,2,3,5,8]
# Object
obj["c", JSON3.JSONObject] # JSON3.JSONObject 

# Data is accessed by iterating over the fields.
# When fields are orders, it is possible to access them sequentially:
cursor = findcursor(obj, "a") # JSON3.Cursor
cursor2 = findcursor(obj, "b", cursor) # iterates from cursor
obj[cursor2] # obj["b"] 

```

# JSON3.jl

## Builtin types

-high-level functions
-JSON3.Object
-JSON3.Array
-String, Int64, Float64, Bool, Nothing

-semi-lazy parsing, compact, fast

## Struct API

### DataTypes
-high-level functions
-Struct
-Mutable
-names, excludes, omitempties

### JSONTypes
-ObjectType: iterate (k, v), T(x::Dict)
-ArrayType: iterate, T(x::Vector)
-StringType: AbstractString interface for writing, T(x::String)
-NumberType: numbertype(T)(x::T) for writing, T(x::numbertype(T)) for reading
-BoolType: Bool(x::T), T(x::Bool)
-NullType: "null", T()

### AbstractTypes
-subtypekey
-subtypes
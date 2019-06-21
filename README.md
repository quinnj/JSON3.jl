# JSON3.jl

*Yet another JSON package for Julia; this one is for speed and struct mapping*

[![Build Status](https://travis-ci.org/quinnj/JSON3.jl.svg?branch=master)](https://travis-ci.org/quinnj/JSON3.jl)
[![Codecov](https://codecov.io/gh/quinnj/JSON3.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/quinnj/JSON3.jl)

**TL;DR**
```julia
# builtin reading/writing
JSON3.read(json_string)
JSON3.write(x)

# custom types
JSON3.read(json_string, T)
JSON3.write(x)
```

## Builtin types

The JSON format is made up of just a few types: Object, Array, String, Number, Bool, and Null.
In the JSON3 package, there are two main interfaces for interacting with these JSON types: 1) builtin and 2) struct mapping.
For builtin reading, called like `JSON3.read(json_string)`, the JSON3 package will parse a string or `Vector{UInt8}`,
returning a default object that maps to the type of the JSON. For a JSON Object, it will return a `JSON3.Object` type, which
acts like a Julia `Dict`, but has a more efficient representation. For a JSON Array, it will return a `JSON3.Array` type,
which acts like a Julia `Vector`, but also has a more efficient representation. If the JSON Array has homogenous elements,
the resulting `JSON3.Array` will be strongly typed accordingly. For the other JSON types (string, number, bool, and null),
they are returned as Julia equivalents (`String`, `Int64` or `Float64`, `Bool`, and `nothing`).

One might wonder why custom `JSON3.Object` and `JSON3.Array` types exist instead of just returning `Dict` and `Vector` directly. JSON3 employs a novel technique [inspired by the simdjson project](https://github.com/lemire/simdjson), that is a 
semi-lazy parsing of JSON to the `JSON3.Object` or `JSON3.Array` types. The technique involves using a type-less "tape" to note
the ***positions*** of objects, arrays, and strings in a JSON structure, while avoiding the cost of ***materializing*** such
objects. For "scalar" types (number, bool, and null), the values are parsed immediately and stored inline in the "tape". This can result in best of both worlds performance: very fast initial parsing of a JSON input, and very cheap access afterwards. It also enables efficiencies in workflows where only small pieces of a JSON structure are needed, because expensive objects, arrays, and strings aren't materialized unless accessed. One additional advantage this technique allows is strong typing of `JSON3.Array{T}`; because the type of each element is noted while parsing, the `JSON3.Array` object can then be constructed with the most narrow type possible without having to reallocate any underlying data (since all data is stored in a type-less "tape" anyway).

The `JSON3.Object` supports the `AbstactDict` interface, but is read-only (it represents a ***view*** into the JSON string input), thus it supports `obj[:x]` and `obj["x"]`, as well as `obj.x` for accessing fields. It supports `keys(obj)` to see available keys in the object structure. You can call `length(obj)` to see how many key-value pairs there are, and it iterates `(k, v)` pairs like a normal `Dict`. It also supports the regular `get(obj, key, default)` family of methods.

The `JSON3.Array{T}` supports the `AbstractArray` interface, but like `JSON3.Object` is a ***view*** into the input JSON, hence is read-only. It supports normal array methods like `length(A)`, `size(A)`, iteration, and `A[i]` `getindex` methods.

## Struct API

The builtin JSON API in JSON3 is efficient and simple, but sometimes a direct mapping to a Julia structure is desirable. JSON3 provides simple, yet powerful "struct mapping" techniques for a few different use-cases, using the `JSON3.StructType` trait specification.

In general, custom Julia types tend to be one of: 1) "data types", 2) "interface types" and sometimes 3) "abstract types" with a known set of concrete subtypes. Data types tend to be "collection of fields" kind of types; fields are generally public and directly accessible, they might also be made to model "objects" in the object-oriented sense. In any case, the type is "nominal" in the sense that it's "made up" of the fields it has, sometimes even if just for making it more convenient to pass them around together in functions.

Interface types, on the other hand, are characterized by ***private*** fields; they contain optimized representations "under the hood" to provide various features/functionality and are useful via interface methods implemented: iteration, `getindex`, accessor methods, etc. Many package-provided libraries or Base-provided structures are like this: `Dict`, `Array`, `Socket`, etc. For these types, their underlying fields are mostly cryptic and provide little value to users directly, and are often explictly documented as being implementation details and not to be accessed under warning of breakage.

What does all this have to do with mapping Julia structures to JSON? A lot! For data types, the most typical JSON representation is for each field name to be a JSON key, and each field value to be a JSON value. And when ***reading*** data types from JSON, we need to specify how to construct the Julia structure for the key-value pairs encountered while parsing. This can be considered a "direct" mapping of Julia struct types to JSON objects in that we try to map field to key directly.

For interface types, however, we don't want to consider the type's fields at all, since they're "private" and not very meaningful. For these types, an alternative API is provided where a user can specify the `JSON3.JSONType` their type most closely maps to, one of `JSON3.ObjectType()`, `JSON3.ArrayType()`, `JSON3.StringType()`, `JSON3.NumberType()`, `JSON3.BoolType()`, or `JSON3.NullType()`.

For abstract types, it can sometimes be useful when reading a JSON structure to say that it will be one of a limited set of related types, with a specific JSON key in the structure signaling which concrete type the rest of the structure represents. JSON3 provides functionality to specify a `JSON3.AbstractType()` for a type, along with a mapping of JSON key-type values to Julia subtypes that can be used to identify the concrete type while parsing.

### DataTypes

For "data types", we aim to directly specify the JSON reading/writing behavior with respect to a Julia type's fields. This kind of data type can signal its struct type in one of two ways:
```julia
JSON3.StructType(::Type{MyType}) = JSON3.Struct()
# or
JSON3.StructType(::Type{MyType}) = JSON3.Mutable()
```
While the default `StructType` for custom types is `JSON3.Struct()`, it is less flexible, yet more performant. For reading a `JSON3.Struct()` from a JSON string input, each key-value pair is read in the order it is encountered in the JSON input, the keys are ignored, and the values are directly passed to the type at the end of the object parsing like `MyType(val1, val2, val3)`. Yes, the JSON specification says that Objects are specifically ***un-ordered*** collections of key-value pairs, but the truth is that many JSON libraries provide ways to maintain JSON Object key-value pair order when reading/writing. Because of the minimal processing done while parsing, and the "trusting" that the Julia type constructor will be able to handle fields being present, missing, or even extra fields that should be ignored, this is the fastest possible method for mapping a JSON input to a Julia structure. If your workflow interacts with non-Julia APIs for sending/receiving JSON, you should take care to test and confirm the use of `JSON3.Struct()` in the cases mentioned above: what if a field is missing when parsing? what if the key-value pairs are out of order? what if there extra fields get included that weren't anticipated? If your workflow is questionable on these points, or it would be too difficult to account for these scenarios in your type constructor, it would be better to consider the `JSON3.Mutable()` option.

The slightly less performant, yet much more robust method for directly mapping Julia struct fields to JSON objects is via `JSON3.Mutable()`. This technique requires your Julia type to be defined, ***at a minimum***, like:
```julia
mutable struct MyType
    field1
    field2
    field3
    # etc.

    MyType() = new()
end
```
Note specifically that we're defining a `mutable struct` to allow field mutation, and providing a `MyType() = new()` inner constructor which constructs an "empty" `MyType` where isbits fields will be randomly initialied, and reference fields will be `#undef`. (Note that the inner constructor doesn't need to be ***exactly*** this, but at least needs to be callable like `MyType()`. If certain fields need to be intialized or zeroed out for security, then this should be accounted for in the inner constructor). For these mutable types, the type will first be initizlied like `MyType()`, then JSON parsing will parse each key-value pair in a JSON object, setting the field as the key is encountered, and converting the JSON value to the appropriate field value. This flow has the nice properties of: allowing parsing success even if fields are missing in the JSON structure, and if "extra" fields exist in the JSON structure that aren't apart of the Julia struct's fields, it will automatically be ignored. This allows for maximum robustness when mapping Julia types to arbitrary JSON objects that may be generated via web services, other language JSON libraries, etc.

There are a few additional helper methods that can be utilized by `JSON3.Mutable()` types to hand-tune field reading/writing behavior:

* `JSON3.names(::Type{MyType}) = ((:field1, :json1), (:field2, :json2))`: provides a mapping of Julia field name to expected JSON object key name. This affects both reading and writing. When reading the `json1` key, the `field1` field of `MyType` will be set. When writing the `field2` field of `MyType`, the JSON key will be `json2`.
* `JSON3.excludes(::Type{MyType}) = (:field1, :field2)`: specify fields of `MyType` to ignore when reading and writing, provided as a `Tuple` of `Symbol`s. When reading, if `field1` is encountered as a JSON key, it's value will be read, but the field will not be set in `MyType`. When writing, `field1` will be skipped when writing out `MyType` fields as key-value pairs.
* `JSON3.omitempties(::Type{MyType}) = (:field1, :field2)`: specify fields of `MyType` that shouldn't be written if they are "empty", provided as a `Tuple` of `Symbol`s. This only affects writing. If a field is a collection (AbstractDict, AbstractArray, etc.) and `isempty(x) === true`, then it will not be written. If a field is `#undef`, it will not be written. If a field is `nothing`, it will not be written. 

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
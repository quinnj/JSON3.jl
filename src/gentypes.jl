@static if Base.VERSION < v"1.2"
    function hasfield(::Type{T}, name::Symbol) where {T}
        return name in fieldnames(T)
    end
    fieldtypes(::Type{T}) where {T} = Tuple(fieldtype(T, i) for i = 1:fieldcount(T))
end

# top type - unifying a type with top yeilds the type
struct Top end

# get the type from a named tuple, given a name
get_type(NT, k) = hasfield(NT, k) ? fieldtype(NT, k) : Nothing

# unify two types to a single type
function promoteunion(T, S)
    new = promote_type(T, S)
    return isabstracttype(new) ? Union{T, S} : new
end

# get the type of the contents
type_or_eltype(::Type{Vector{T}}) where {T} = T
type_or_eltype(::Type{T}) where {T} = T

unify(a, b) = unify(b, a)
unify(a::Type{T}, b::Type{S}) where {T,S} = promoteunion(T, S)
unify(a::Type{T}, b::Type{S}) where {T,S<:T} = T
unify(a::Type{Top}, b::Type{T}) where {T} = T

function unify(
    a::Type{NamedTuple{A,T}},
    b::Type{NamedTuple{B,S}},
) where {A,T<:Tuple,B,S<:Tuple}
    ks = []
    ts = []
    for (k, v) in zip(A, fieldtypes(a))
        push!(ks, k)
        push!(ts, unify(v, get_type(b, k)))
    end

    for (k, v) in zip(B, fieldtypes(b))
        if !(k in ks)
            push!(ks, k)
            push!(ts, unify(v, Nothing))
        end
    end

    return NamedTuple{tuple(ks...),Tuple{ts...}}
end

unify(a::Type{Vector{T}}, b::Type{Vector{S}}) where {T,S} = Vector{unify(T, S)}

# parse json into a type, maintain field order
"""
    JSON3.generate_type(json)

Given a JSON3 Object or Array, return a "raw type" from it.  A raw type is typically a `NamedTuple`, which can contain further nested `NamedTuples`, concrete, `Array`, or `Union` types.
"""
function generate_type(o::JSON3.Object)
    ks = []
    ts = []
    for (k, v) in o
        push!(ks, k)
        push!(ts, generate_type(v))
    end

    return NamedTuple{tuple(ks...),Tuple{ts...}}
end

function generate_type(a::JSON3.Array)
    t = Set([])
    nt = Top
    for item in a
        it = generate_type(item)
        if it <: NamedTuple
            nt = unify(nt, it)
        else
            push!(t, it)
        end
    end

    return Vector{foldl(unify, t; init = Union{nt})}
end

generate_type(x::T) where {T} = T

# get the AST of a type
function to_ast(::Type{T}) where {T}
    io = IOBuffer()
    print(io, T)
    str = String(take!(io))
    ast = Meta.parse(str)
    return ast
end

# make a field identifer into pascal case for struct name (my_names => MyName)
function pascalcase(s::Symbol)
    str = String(s)
    new_str = ""
    next_upper = true
    for letter in str
        if next_upper
            new_str *= uppercase(letter)
            next_upper = false
        elseif letter == '_'
            next_upper = true
        else
            new_str *= letter
        end
    end

    if length(new_str) > 1 && new_str[end] == 's' && new_str[end-1:end] != "ss"
        new_str = new_str[1:end-1]
    end

    return Symbol(new_str)
end

"""
    JSON3.write_exprs(expr, f)

Write an `Expr` or `Vector{Expr}` to file.  Formatted so that it can be used with `include`.
"""
function write_exprs(expr::Expr, io::IOStream)
    str = repr(expr)[3:end-1] # removes :( and )
    str = replace(str, "\n  " => "\n") # un-tab each line
    Base.write(io, str)
    Base.write(io, "\n\n")
end

function write_exprs(exprs::Vector, fname::AbstractString)
    open(fname, "w") do io
        for expr in exprs
            write_exprs(expr, io)
        end
    end
end

function write_exprs(expr::Expr, fname::AbstractString)
    open(fname, "w") do io
        write_exprs(expr, io)
    end
end

# entry function for turning a "raw" type from `generate_type` to Exprs
"""
    JSON3.generate_exprs(raw_type; root_name=:Root, mutable=true)

Generate a vector of `Expr` from a "raw_type".  This will un-nest any sub-types within the root type.

The name of the root type is from the `name` variable (default :Root), then nested types are named from the key that they live under in the JSON.  The key is transformed to be pascal case and singular.

If `mutable` is `true`, an empty constructor is included in the struct definition. This allows the mutable structs to be used with `StructTypes.Mutable()` out of the box.
"""
function generate_exprs(t; root_name::Symbol = :Root, mutable = true)
    exprs = []
    generate_expr!(exprs, t, root_name; mutable = mutable)
    return exprs
end

# turn a "raw" type into an AST for a struct
function generate_expr!(
    exprs,
    nt::Type{NamedTuple{N,T}},
    root_name::Symbol;
    mutable::Bool = true,
) where {N,T<:Tuple}
    sub_exprs = []
    for (n, t) in zip(N, fieldtypes(nt))
        push!(sub_exprs, generate_field_expr!(exprs, t, n; mutable = mutable))
    end

    struct_name = pascalcase(root_name)
    if mutable
        push!(sub_exprs, Meta.parse("$struct_name() = new()"))
    end

    push!(exprs, Expr(:struct, mutable, struct_name, Expr(:block, sub_exprs...)))
    return struct_name
end

# should only hit this in the case of the array being the root of the type
function generate_expr!(
    exprs,
    ::Type{Base.Array{T,N}},
    root_name::Symbol;
    kwargs...,
) where {T<:NamedTuple,N}
    return generate_expr!(exprs, T, root_name; kwargs...)
end

function generate_expr!(exprs, t::Type{T}, root_name::Symbol; kwargs...) where {T}
    if T isa Union
        return Expr(
            :curly,
            :Union,
            generate_expr!(exprs, t.a, root_name; kwargs...),
            generate_expr!(exprs, t.b, root_name; kwargs...),
        )
    else
        return to_ast(T)
    end
end

# given the type of a field of a struct, return a node for that field's name/type
function generate_field_expr!(
    exprs,
    t::Type{NamedTuple{N,T}},
    root_name::Symbol;
    kwargs...,
) where {N,T}
    generate_expr!(exprs, t, root_name; kwargs...)
    return Expr(:(::), root_name, pascalcase(root_name))
end

function generate_field_expr!(
    exprs,
    ::Type{Base.Array{T,N}},
    root_name::Symbol;
    kwargs...,
) where {T,N}
    return Expr(
        :(::),
        root_name,
        Expr(:curly, :Array, generate_expr!(exprs, T, root_name; kwargs...), 1),
    )
end

function generate_field_expr!(exprs, ::Type{T}, root_name::Symbol; kwargs...) where {T}
    return Expr(:(::), root_name, generate_expr!(exprs, T, root_name; kwargs...))
end

# create a module with the struct declarations as well as the StructType declarations
"""
    JSON3.generate_struct_type_module(exprs, module_name)

Given a vector of `exprs` (output of [`generate_exprs`](@ref)), return an `Expr` containing the AST for a module with name `module_name`.  The module will map all types to the appropriate `StructType`, so the result can immediately used with `JSON3.read(json, T)`.
"""
function generate_struct_type_module(exprs, module_name)
    mutable = exprs[1].args[1]
    struct_type_import = Meta.parse("import StructTypes")
    struct_type = mutable ? "Mutable" : "Struct"
    struct_type_decls = []
    for expr in exprs
        push!(
            struct_type_decls,
            Meta.parse("StructTypes.StructType(::Type{$(expr.args[2])}) = StructTypes.$struct_type()"),
        )
    end
    type_block = Expr(:block, struct_type_import, exprs..., struct_type_decls...)
    return Expr(:module, true, module_name, type_block)
end

"""
    JSON3.generatetypes(json, module_name; mutable=true, root_name=:Root)

Convenience function to go from a json string or file name to an AST with a module of structs.

Performs the following:
1. If the JSON is a file, read to string
2. Call `JSON3.read` on the JSON string
3. Get the "raw type" from [`generate_type`](@ref)
4. Parse the "raw type" into a vector of `Expr` ([`generate_exprs`](@ref))
5. Generate a module containg the structs ([`generate_struct_type_module`](@ref))
"""
function generatetypes(
    json_str::AbstractString,
    module_name::Symbol;
    mutable::Bool = true,
    root_name::Symbol = :Root,
)
    # either a JSON.Array or JSON.Object
    json = read(
        length(json_str) < 255 && isfile(json_str) ? Base.read(json_str, String) :
            json_str,
    )

    # build a type for the JSON
    raw_json_type = generate_type(json)
    json_exprs = generate_exprs(raw_json_type; root_name=root_name, mutable=mutable)
    return generate_struct_type_module(
        json_exprs,
        module_name
    )
end

read_json_str(json_str) = read(length(json_str) < 255 && isfile(json_str) ? Base.read(json_str, String) : json_str)

function generatetypes(
    json_str::Vector{<:AbstractString},
    module_name::Symbol;
    mutable::Bool = true,
    root_name::Symbol = :Root,
)
    # either a JSON.Array or JSON.Object
    json = read_json_str.(json_str)

    # build a type for the JSON
    raw_json_type = reduce(unify, type_or_eltype.(generate_type.(json)); init=Top)
    json_exprs = generate_exprs(raw_json_type; root_name=root_name, mutable=mutable)
    return generate_struct_type_module(
        json_exprs,
        module_name
    )
end

# macro to create a module with types generated from a json string
"""
    JSON3.@generatetypes json [module_name]

Evaluate the result of the [`generatetypes`](@ref) function in the current scope.
"""
macro generatetypes(json_str, module_name)
    :(Core.eval($__module__, generatetypes($(esc(json_str)), $(esc(module_name)))))
end

macro generatetypes(json)
    :(@generatetypes $(esc(json)) :JSONTypes)
end

# convenience function to go from json_string, to file with module
"""
    JSON3.writetypes(json, file_name; module_name=:JSONTypes, root_name=:Root, mutable=true)

Write the result of the [`generatetypes`](@ref) function to file.
"""
function writetypes(
    json,
    file_name;
    module_name::Symbol = :JSONTypes,
    root_name::Symbol = :Root,
    mutable::Bool = true,
)
    mod = generatetypes(json, module_name; mutable=mutable, root_name=root_name)
    write_exprs(mod, file_name)
end

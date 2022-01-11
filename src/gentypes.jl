@static if Base.VERSION < v"1.2"
    function hasfield(::Type{T}, name::Symbol) where {T}
        return name in fieldnames(T)
    end
    fieldtypes(::Type{T}) where {T} = Tuple(fieldtype(T, i) for i = 1:fieldcount(T))
end

# get the type from a named tuple, given a name
get_type(NT, k) = hasfield(NT, k) ? fieldtype(NT, k) : Nothing

# if a union contains two named tuples, unify them
# if union length is > 2, u.b will have continuing fields
function unify_union(u)
    if !isa(u.b, Union)
        # because of unify methods, only need to worry about unions with len > 2
        return u
    end

    # unions are sorted alphabetically, so pairs of super types will always be adjacent
    type = Union{}
    union_types = Base.uniontypes(u)
    i = 1
    while i <= Base.unionlen(u)
        cur = union_types[i]

        # no more nexts to compare to
        if i == Base.unionlen(u)
            type = Union{type,cur}
            break
        end

        next = union_types[i+1]
        if cur <: Vector && next <: Vector
            type = Union{type,unify(cur, next)}
            i += 2
        elseif cur <: NamedTuple && next <: NamedTuple
            type = Union{type,unify(cur, next)}
            i += 2
        else
            type = Union{type,cur}
            i += 1
        end
    end

    return type
end

# unify two types to a single type
function promoteunion(::Type{T}, ::Type{S}) where {T,S}
    new = promote_type(T, S)
    if !isabstracttype(new) && isconcretetype(new)
        return new
    else
        return unify_union(Union{T,S})
    end
end

# get the type of the contents
type_or_eltype(::Type{Vector{T}}) where {T} = T
type_or_eltype(::Type{T}) where {T} = T

unify(a::Type{T}, b::Type{S}) where {T,S} = promoteunion(T, S)
unify(a::Type{T}, b::Type{S}) where {T,S<:T} = T
unify(b::Type{S}, a::Type{T}) where {T,S<:T} = T
unify(a::Type{T}, b::Type{T}) where {T} = T
unify(a::Type{Any}, b::Type{T}) where {T} = T
unify(b::Type{T}, a::Type{Any}) where {T} = T
unify(a::Type{Any}, b::Type{Any}) = Any

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
unify(a::Type{NamedTuple{A,T}}, b::Type{NamedTuple{A,T}}) where {A,T<:Tuple} =
    NamedTuple{A,T}

unify(a::Type{Vector{T}}, b::Type{Vector{S}}) where {T,S} = Vector{unify(T, S)}
unify(a::Type{Vector{T}}, b::Type{Vector{T}}) where {T} = Vector{T}

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
    if isempty(a)
        return Vector{Any}
    end

    t = Set([])
    nt = Any
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

# remove line number nodes
function remove_line_numbers!(expr::Expr)
    filter!(x -> !isa(x, LineNumberNode), expr.args)
    for arg in expr.args
        remove_line_numbers!(arg)
    end
end
remove_line_numbers!(x) = nothing # no-op fallback

# collapse singleton blocks into just the contained Expr
function collapse_singleton_blocks!(expr::Expr)
    if expr.head == :block && length(expr.args) == 1
        expr.head = expr.args[1].head
        expr.args = expr.args[1].args
    end

    for arg in expr.args
        collapse_singleton_blocks!(arg)
    end
end
collapse_singleton_blocks!(x) = nothing # no-op fallback

isunion(expr::Expr) = expr.head == :curly && length(expr.args) > 0 && expr.args[1] == :Union
isunion(x) = false # fallback

# Union{A, Union{B, C}} => Union{A, B, C}
function collapse_unions!(expr::Expr)
    if isunion(expr) && isunion(expr.args[end])
        u = pop!(expr.args)
        append!(expr.args, u.args[2:3])
        collapse_unions!(expr) # catch more nested unions
    end

    for arg in expr.args
        collapse_unions!(arg)
    end
end
collapse_unions!(x) = nothing # no-op fallback

# from https://docs.julialang.org/en/v1/base/base/#Keywords
const RESERVED_WORDS = (
    :baremodule,
    :begin,
    :break,
    :catch,
    :const,
    :continue,
    :do,
    :else,
    :elseif,
    :end,
    :export,
    :false,
    :finally,
    :for,
    :function,
    :global,
    :if,
    :import,
    :let,
    :local,
    :macro,
    :module,
    :quote,
    :return,
    :struct,
    :true,
    :try,
    :using,
    :while,
)

is_valid_fieldname(x::Symbol) = Base.isidentifier(x) && !(x in RESERVED_WORDS)
is_valid_fieldname(x) = true # fallback for cases outside of x::Int

# end::Int => var"#JSON3_ESCAPE_THIS#end"::Int (the escape token gets removed later)
const JSON3_ESCAPE_TOKEN = "#JSON3_ESCAPE_THIS#"
@static if Base.VERSION < v"1.3"
    function escape_variable_names!(expr::Expr)
        if expr.head == :(::)
            if !is_valid_fieldname(expr.args[1])
                @warn """Invalid identifier found: $(expr.args[1]).

                In the types written to file, rename the field in the struct to a valid identifier and add a line `StructTypes.names(::Type{MyType}) = ((:julia_field_name, :json_field_name))` with the affected type, new Julia field name, and original JSON field name."""
            end
        else
            for arg in expr.args
                escape_variable_names!(arg)
            end
        end
    end
else
    function escape_variable_names!(expr::Expr)
        if expr.head == :(::)
            if !is_valid_fieldname(expr.args[1])
                # if the variable name is invalid, it will be escaped by `repr` later. This
                # token is used to force reserved keywords to be marked as invalid and will
                # be removed in `write_expr`..
                expr.args[1] = Symbol("$JSON3_ESCAPE_TOKEN$(expr.args[1])")
            end
        else
            for arg in expr.args
                escape_variable_names!(arg)
            end
        end
    end
end
escape_variable_names!(x) = nothing # no-op fallback

"""
    JSON3.write_exprs(expr, f)

Write an `Expr` or `Vector{Expr}` to file.  Formatted so that it can be used with `include`.
"""
function write_exprs(expr::Expr, io::IOStream)
    remove_line_numbers!(expr)
    collapse_unions!(expr)
    collapse_singleton_blocks!(expr)
    escape_variable_names!(expr)

    str = repr(expr)[3:end-1] # removes :( and )
    str = replace(str, "\n  " => "\n") # un-tab each line
    str = replace(str, JSON3_ESCAPE_TOKEN => "") # remove the escape token

    # better spacing
    str = replace(str, "end\n" => "end\n\n")
    str = replace(str, r"(module \w+)" => @s_str("\\1\n"))
    str = replace(str, r"(import \w+)" => @s_str("\\1\n"))
    str = str[1:end-3] * "\nend # module\n"

    Base.write(io, str)

    return nothing
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
    types = []
    flatten_types!(types, t, root_name)
    types = unify_types(types)
    return map(x -> generate_expr(x.second, x.first; mutable = mutable), types)
end

# if multiple types have the same root name, unify them into one type
function unify_types(types)
    new_types = []
    for t in types
        i = findfirst(x -> x.first == t.first, new_types)
        if isnothing(i)
            push!(new_types, t)
        else
            new_types[i] = (t.first => unify(new_types[i].second, t.second))
        end
    end

    return new_types
end

# flatten a nested named tuple type into a vector of (name => named tuple)
function flatten_types!(
    types,
    nt::Type{NamedTuple{N,T}},
    root_name::Symbol,
) where {N,T<:Tuple}
    ns = []
    ts = []

    for (n, t) in zip(N, fieldtypes(nt))
        push!(ns, n)
        push!(ts, flatten_types!(types, t, n))
    end

    push!(types, (root_name => NamedTuple{tuple(ns...),Tuple{ts...}}))

    # if a nested named tuple, return the name of the type instead of the signature
    return Val{pascalcase(root_name)}
end

# should only hit this in the case of the array being the root of the type
function flatten_types!(
    types,
    ::Type{Base.Array{T,N}},
    root_name::Symbol,
) where {T<:NamedTuple,N}
    return Vector{flatten_types!(types, T, root_name)}
end

function flatten_types!(types, t::Type{T}, root_name::Symbol) where {T}
    if T isa Union
        return Union{
            flatten_types!(types, t.a, root_name),
            flatten_types!(types, t.b, root_name),
        }
    else
        return t
    end
end

# turn a "raw" type into an AST for a struct
function generate_expr(
    nt::Type{NamedTuple{N,T}},
    root_name::Symbol;
    mutable::Bool = true,
) where {N,T<:Tuple}
    struct_name = pascalcase(root_name)

    sub_exprs = []
    for (n, t) in zip(N, fieldtypes(nt))
        push!(sub_exprs, Expr(:(::), n, generate_field_expr(t)))
    end

    if mutable
        push!(sub_exprs, Meta.parse("$struct_name() = new()"))
    end

    return Expr(:struct, mutable, struct_name, Expr(:block, sub_exprs...))
end

# given the type of a field of a struct, return a node for that field's name/type
function generate_field_expr(t::Type{Val{N}}) where {N}
    return N
end

function generate_field_expr(::Type{Base.Array{T,N}}) where {T,N}
    return Expr(:curly, :Array, generate_field_expr(T), 1)
end

function generate_field_expr(t::Type{T}) where {T}
    if T isa Union
        return Expr(:curly, :Union, generate_field_expr(t.a), generate_field_expr(t.b))
    else
        return to_ast(T)
    end
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
            Meta.parse(
                "StructTypes.StructType(::Type{$(expr.args[2])}) = StructTypes.$struct_type()",
            ),
        )
    end
    type_block = Expr(:block, struct_type_import, exprs..., struct_type_decls...)
    return Expr(:module, true, module_name, type_block)
end

read_json_str(json_str) = read(
    length(json_str) < 255 && isfile(json_str) ? Base.read(json_str, String) : json_str,
)

"""
    JSON3.generatetypes(json, module_name; mutable=true, root_name=:Root)

Convenience function to go from a json string, an array of json strings, or a file name to an AST with a module of structs.

Performs the following:
1. If the JSON is a file, read to string
2. Call `JSON3.read` on the JSON string
3. Get the "raw type" from [`generate_type`](@ref)
4. Parse the "raw type" into a vector of `Expr` ([`generate_exprs`](@ref))
5. Generate an AST with the module containg the structs ([`generate_struct_type_module`](@ref))
"""
function generatetypes(
    json_str::AbstractString,
    module_name::Symbol;
    mutable::Bool = true,
    root_name::Symbol = :Root,
)
    # either a JSON.Array or JSON.Object
    json = read_json_str(json_str)

    # build a type for the JSON
    raw_json_type = generate_type(json)
    json_exprs = generate_exprs(raw_json_type; root_name = root_name, mutable = mutable)
    return generate_struct_type_module(json_exprs, module_name)
end

function generatetypes(
    json_str::Vector{<:AbstractString},
    module_name::Symbol;
    mutable::Bool = true,
    root_name::Symbol = :Root,
)
    # either a JSON.Array or JSON.Object
    json = read_json_str.(json_str)

    # build a type for the JSON
    raw_json_type = reduce(unify, type_or_eltype.(generate_type.(json)); init = Any)
    json_exprs = generate_exprs(raw_json_type; root_name = root_name, mutable = mutable)
    return generate_struct_type_module(json_exprs, module_name)
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
    mod = generatetypes(json, module_name; mutable = mutable, root_name = root_name)
    write_exprs(mod, file_name)
end

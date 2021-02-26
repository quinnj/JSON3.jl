@static if Base.VERSION < v"1.2"
    function hasfield(::Type{T}, name::Symbol) where T
        return name in fieldnames(T)
    end
    fieldtypes(::Type{T}) where {T} = Tuple(fieldtype(T, i) for i = 1:fieldcount(T))
end

# top type - unifying a type with top yeilds the type
struct Top end

# get the type from a named tuple, given a name
get_type(NT, k) = hasfield(NT, k) ? fieldtype(NT, k) : Nothing

# unify two types to a single type
unify(a, b) = unify(b, a)
unify(a::Type{T}, b::Type{S}) where {T,S} = Base.promote_typejoin(T, S)
unify(a::Type{T}, b::Type{S}) where {T,S<:T} = T
unify(a::Type{Top}, b::Type{T}) where {T} = T

function unify(
    a::Type{NamedTuple{A,T}},
    b::Type{NamedTuple{B,S}},
) where {A,T<:Tuple,B,S<:Tuple}
    c = Dict()
    for (k, v) in zip(A, fieldtypes(a))
        c[k] = unify(v, get_type(b, k))
    end

    for (k, v) in zip(B, fieldtypes(b))
        if !haskey(c, k)
            c[k] = unify(v, Nothing)
        end
    end

    return NamedTuple{tuple(keys(c)...),Tuple{values(c)...}}
end

unify(a::Type{Vector{T}}, b::Type{Vector{S}}) where {T,S} = Vector{unify(T, S)}

# parse json into a type
function generate_type(o::JSON3.Object)
    d = Dict()
    for (k, v) in o
        d[k] = generate_type(v)
    end

    return NamedTuple{tuple(keys(d)...),Tuple{values(d)...}}
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

# make a field identifer into pascal case for struct name (my_name => MyName)
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

    if new_str[end] == 's'
        if new_str[end-2:end] == "ies"
            new_str = new_str[1:end-3] * "y"
        else
            new_str = new_str[1:end-1]
        end
    end

    return Symbol(new_str)
end

# write the structs to file
function write_exprs(exprs::Vector, fname::AbstractString)
    open(fname, "w") do io
        for expr in exprs
            str = repr(expr)[3:end-1] # removes :( and )
            str = replace(str, "\n  " => "\n") # un-tab each line
            Base.write(io, str)
            Base.write(io, "\n\n")
        end
    end
end

# entry function for turning a "raw" type from `generate_type` to Exprs
function generate_exprs(t, name::Symbol=:Root)
    exprs = []
    generate_expr!(exprs, t, name)
    return exprs
end

# turn a "raw" type into an AST for a struct
function generate_expr!(exprs, nt::Type{NamedTuple{N,T}}, root_name::Symbol) where {N,T<:Tuple}
    sub_exprs = []
    for (n, t) in zip(N, fieldtypes(nt))
        push!(sub_exprs, generate_field_expr!(exprs, t, n))
    end
    struct_name = pascalcase(root_name)
    push!(exprs, Expr(:struct, false, struct_name, Expr(:block, sub_exprs...)))
    return struct_name
end

# should only hit this in the case of the array being the root of the type
function generate_expr!(exprs, ::Type{Base.Array{T,N}}, root_name::Symbol) where {T<:NamedTuple,N}
    return generate_expr!(exprs, T, root_name)
end

function generate_expr!(exprs, t::Type{T}, root_name::Symbol) where {T}
    if T isa Union
        return Expr(
            :curly,
            :Union,
            generate_expr!(exprs, t.a, root_name),
            generate_expr!(exprs, t.b, root_name),
        )
    else
        return to_ast(T)
    end
end

# given the type of a field of a struct, return a node for that field's name/type
function generate_field_expr!(exprs, t::Type{NamedTuple{N,T}}, root_name::Symbol) where {N,T}
    generate_expr!(exprs, t, root_name)
    return Expr(:(::), root_name, pascalcase(root_name))
end

function generate_field_expr!(exprs, ::Type{Base.Array{T,N}}, root_name::Symbol) where {T,N}
    return Expr(:(::), root_name, Expr(:curly, :Array, generate_expr!(exprs, T, root_name), 1))
end

function generate_field_expr!(exprs, ::Type{T}, root_name::Symbol) where {T}
    return Expr(:(::), root_name, generate_expr!(exprs, T, root_name))
end


macro generatetypes(json_str, name)
    return quote
        # either a JSON.Array or JSON.Object
        local json = JSON3.read(length($(esc(json_str))) < 255 && isfile($(esc(json_str))) ? read($(esc(json_str))) : $(esc(json_str)))

        # build a type for the JSON
        local raw_json_type = JSON3.generate_type(json)
        local json_exprs = JSON3.generate_exprs(raw_json_type, $(esc(name)))
        local exprs = Expr(:block, json_exprs...)
        return Core.eval($__module__, exprs)
    end
end

macro generatetypes(json)
    :(@generatetypes $(esc(json)) :Root)
end

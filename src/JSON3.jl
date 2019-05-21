module JSON3

using Parsers, Mmap

struct Object <: AbstractDict{Symbol, Any}
    buf::Base.CodeUnits{UInt8,String}
    tape::Vector{UInt64}
end

Object() = Object(codeunits(""), UInt64[object(2), 0])

struct Array{T} <: AbstractVector{T}
    buf::Base.CodeUnits{UInt8,String}
    tape::Vector{UInt64}
end

getbuf(j::Union{Object, Array}) = getfield(j, :buf)
gettape(j::Union{Object, Array}) = getfield(j, :tape)

include("utils.jl")

@noinline invalid(error, buf, pos, T) = throw(ArgumentError("""
invalid JSON at byte position $pos while parsing type $T: $error
$(String(buf[max(1, pos-10):min(end, pos+10)]))
"""))
@enum Error UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedComma ExpectedSemiColon InvalidChar

# AbstractDict interface
function Base.length(obj::Object)
    @inbounds len = getnontypemask(gettape(obj)[2])
    return len
end

@inline function Base.iterate(obj::Object, (i, tapeidx)=(1, 3))
    i > length(obj) && return nothing
    tape = gettape(obj)
    @inbounds t = tape[tapeidx]
    key = getvalue(Symbol, getbuf(obj), tape, tapeidx, t)
    tapeidx += 2
    @inbounds t = tape[tapeidx]
    x = Pair{Symbol, Any}(key, getvalue(Any, getbuf(obj), tape, tapeidx, t))
    tapeidx += gettapelen(Any, t)
    return x, (i + 1, tapeidx)
end

function Base.get(obj::Object, key)
    for (k, v) in obj
        k == key && return v
    end
    throw(KeyError(key))
end

function Base.get(obj::Object, ::Type{T}, key)::T where {T}
    for (k, v) in obj
        k == key && return v
    end
    throw(KeyError(key))
end

function Base.get(obj::Object, key, default)
    for (k, v) in obj
        k == key && return v
    end
    return default
end

function Base.get(obj::Object, ::Type{T}, key, default::T)::T where {T}
    for (k, v) in obj
        k == key && return v
    end
    return default
end

function Base.get(default::Base.Callable, obj::Object, key)
    for (k, v) in obj
        k == key && return v
    end
    return default()
end

Base.propertynames(obj::Object) = collect(keys(obj))

Base.getproperty(obj::Object, prop::Symbol) = get(obj, prop)
Base.getindex(obj::Object, str::String) = get(obj, Symbol(str))

# AbstractArray interface
Base.IndexStyle(::Type{<:Array}) = Base.IndexLinear()

function Base.size(arr::Array)
    @inbounds len = getnontypemask(gettape(arr)[2])
    return (len,)
end

function Base.iterate(arr::Array{T}, (i, tapeidx)=(1, 3)) where {T}
    i > length(arr) && return nothing
    tape = gettape(arr)
    @inbounds t = tape[tapeidx]
    val = getvalue(T, getbuf(arr), tape, tapeidx, t)
    tapeidx += gettapelen(T, t)
    return val, (i + 1, tapeidx)
end

@inline Base.@propagate_inbounds function Base.getindex(arr::Array{T}, i::Int) where {T}
    @boundscheck checkbounds(arr, i)
    tape = gettape(arr)
    buf = getbuf(arr)
    if regularstride(T)
        tapeidx = 1 + 2 * i
        @inbounds t = tape[tapeidx]
        return getvalue(T, buf, tape, tapeidx, t)
    else
        tapeidx = 3
        idx = 1
        while true 
            @inbounds t = tape[tapeidx]
            if i == idx
                return getvalue(T, buf, tape, tapeidx, t)
            else
                tapeidx += gettapelen(T, t)
                idx += 1
            end
        end
    end
end

include("read.jl")
include("strings.jl")
include("show.jl")
include("structs.jl")

end # module

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

# Julia structs
  # immutable
    # positional arg or keyword args
  # mutable
    # noarg, positional, or keyword args

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

function Base.get(obj::Object, key, default)
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

function read(str::String)
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        return Object()
    end
    @inbounds b = buf[1]
    tape = len > div(Mmap.PAGESIZE, 2) ? Mmap.mmap(Vector{UInt64}, len) :
        Vector{UInt64}(undef, len + 2)
    pos, tapeidx = read!(buf, 1, len, b, tape, 1, Any)
    @inbounds t = tape[1]
    if isobject(t)
        return Object(buf, tape)
    elseif isarray(t)
        return Array{geteltype(tape[2])}(buf, tape)
    else
        return getvalue(Any, buf, tape, 1, t)
    end
end

function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Any})
    @wh
    if b == UInt8('{')
        return read!(buf, pos, len, b, tape, tapeidx, Object)
    elseif b == UInt8('[')
        return read!(buf, pos, len, b, tape, tapeidx, Array)
    elseif b == UInt8('"')
        return read!(buf, pos, len, b, tape, tapeidx, String)
    elseif b == UInt8('n')
        return read!(buf, pos, len, b, tape, tapeidx, Nothing)
    elseif b == UInt8('t')
        return read!(buf, pos, len, b, tape, tapeidx, True)
    elseif b == UInt8('f')
        return read!(buf, pos, len, b, tape, tapeidx, False)
    elseif (UInt8('0') <= b <= UInt8('9')) || b == UInt8('-') || b == UInt8('+')
        float, code, floatpos = Parsers.typeparser(Float64, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
        if code > 0
            int = unsafe_trunc(Int64, float)
            if int == float
                @inbounds tape[tapeidx] = INT
                @inbounds tape[tapeidx + 1] = Core.bitcast(UInt64, int)
            else
                @inbounds tape[tapeidx] = FLOAT
                @inbounds tape[tapeidx + 1] = Core.bitcast(UInt64, float)
            end
            return floatpos, tapeidx + 2
        end
    end
@label invalid
    invalid(InvalidChar, buf, pos, Any)
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{String})
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    strpos = pos
    strlen = 0
    escaped = false
    @inbounds b = buf[pos]
    # positioned at first character of object key
    while b != UInt8('"')
        if b == UInt8('\\')
            escaped = true
            # skip next character
            pos += 2
            strlen += 2
        else
            pos += 1
            strlen += 1
        end
        @eof
        @inbounds b = buf[pos]
    end
    @inbounds tape[tapeidx] = string(strlen)
    @inbounds tape[tapeidx+1] = ifelse(escaped, ESCAPE_BIT | strpos, strpos)
    return pos + 1, tapeidx + 2

@label invalid
    invalid(error, buf, pos, String)
end

struct True end
@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{True})
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        @inbounds tape[tapeidx] = BOOL | UInt64(1)
        return pos + 4, tapeidx + 2
    else
        invalid(InvalidChar, buf, pos, True)
    end
end

struct False end
@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{False})
    if pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        @inbounds tape[tapeidx] = BOOL
        return pos + 5, tapeidx + 2
    else
        invalid(InvalidChar, buf, pos, False)
    end
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Nothing})
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        @inbounds tape[tapeidx] = NULL
        return pos + 4, tapeidx + 2
    else
        invalid(InvalidChar, buf, pos, Nothing)
    end
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Object})
    objidx = tapeidx
    eT = EMPTY
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8('}')
        @inbounds tape[tapeidx] = object(2)
        @inbounds tape[tapeidx+1] = eltypelen(eT, 0)
        tapeidx += 2
        pos += 1
        @goto done
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    tapeidx += 2
    nelem = 0
    while true
        keypos = pos
        keylen = 0
        escaped = false
        # read first key character
        @inbounds b = buf[pos]
        # positioned at first character of object key
        while b != UInt8('"')
            if b == UInt8('\\')
                escaped = true
                # skip next character
                pos += 2
                keylen += 2
            else
                pos += 1
                keylen += 1
            end
            @eof
            @inbounds b = buf[pos]
        end
        @inbounds tape[tapeidx] = string(keylen)
        @inbounds tape[tapeidx+1] = ifelse(escaped, ESCAPE_BIT | keypos, keypos)
        tapeidx += 2
        pos += 1
        @eof
        @inbounds b = buf[pos]
        @wh
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @eof
        @inbounds b = buf[pos]
        @wh
        # now positioned at start of value
        prevtapeidx = tapeidx
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any)
        @eof
        @inbounds b = buf[pos]
        @wh
        @inbounds eT = promoteeltype(eT, gettypemask(tape[prevtapeidx]))
        nelem += 1
        if b == UInt8('}')
            @inbounds tape[objidx] = object(tapeidx - objidx)
            @inbounds tape[objidx+1] = eltypelen(eT, nelem)
            pos += 1
            @goto done
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        @inbounds b = buf[pos]
        @wh
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        pos += 1
        @eof
    end

@label done
    return pos, tapeidx
@label invalid
    invalid(error, buf, pos, Object)
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Array})
    arridx = tapeidx
    eT = EMPTY
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8(']')
        @inbounds tape[tapeidx] = array(2)
        @inbounds tape[tapeidx+1] = eltypelen(eT, 0)
        tapeidx += 2
        pos += 1
        @goto done
    end
    tapeidx += 2
    nelem = 0
    while true
        # positioned at start of value
        prevtapeidx = tapeidx
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any)
        @eof
        @inbounds b = buf[pos]
        @wh
        @inbounds eT = promoteeltype(eT, gettypemask(tape[prevtapeidx]))
        nelem += 1
        if b == UInt8(']')
            @inbounds tape[arridx] = array(tapeidx - arridx)
            @inbounds tape[arridx+1] = eltypelen(eT, nelem)
            pos += 1
            @goto done
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        @inbounds b = buf[pos]
        @wh
    end

@label done
    return pos, tapeidx
@label invalid
    invalid(error, buf, pos, Array)
end

include("strings.jl")
include("show.jl")
include("structs.jl")

end # module

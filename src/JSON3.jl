module JSON3

using Parsers, Mmap

include("utils.jl")

@noinline invalid(error, b, T) = throw(ArgumentError("invalid JSON: $error. Encountered '$(Char(b))' while parsing type: $T"))
@enum Error UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedComma ExpectedSemiColon InvalidChar

# Julia structs
  # immutable
    # positional arg or keyword args
  # mutable
    # noarg, positional, or keyword args

struct Object{B <: AbstractVector{UInt8}}
    buf::B
    tape::Vector{UInt64}
end

function Base.propertynames(obj::Object)
    tape = gettape(obj)
    buf = getbuf(obj)
    props = Symbol[]
    if getidx(tape[1]) == 1
        return props
    end
    tapeidx = 2
    last = getidx(tape[1])
    while tapeidx <= last
        @inbounds t = tape[tapeidx]
        push!(props, _symbol(pointer(buf, getpos(t)), getlen(t)))
        tapeidx += 1
        @inbounds tapeidx += tapeelements(tape[tapeidx])
    end
    return props
end

function Base.getproperty(obj::Object, prop::Symbol)
    tape = gettape(obj)
    buf = getbuf(obj)
    if getidx(tape[1]) == 1
        return nothing
    end
    tapeidx = 2
    last = getidx(tape[1])
    while tapeidx <= last
        @inbounds t = tape[tapeidx]
        key = _symbol(pointer(buf, getpos(t)), getlen(t))
        if key == prop
            return getvalue(buf, tape, tapeidx + 1)
        else
            tapeidx += 1
            @inbounds tapeidx += tapeelements(tape[tapeidx])
        end
    end
    return nothing
end
Base.getindex(obj::Object, str::String) = getproperty(obj, Symbol(str))

struct Array{B <: AbstractVector{UInt8}}
    buf::B
    tape::Vector{UInt64}
end

getbuf(j::Union{Object, Array}) = getfield(j, :buf)
gettape(j::Union{Object, Array}) = getfield(j, :tape)

# TODO
  # make Array subtype AbstractVector
  # implement interface
  # properly checkbounds
function Base.getindex(arr::Array, i::Int)
    tape = gettape(arr)
    buf = getbuf(arr)
    if getidx(tape[1]) == 1
        return nothing
    end
    tapeidx = 2
    last = getidx(tape[1])
    idx = 1
    while tapeidx <= last
        if i == idx
            return getvalue(buf, tape, tapeidx)
        else
            @inbounds tapeidx += tapeelements(tape[tapeidx])
            idx += 1
        end
    end
    return nothing
end

function read(str::String)
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        return Object(buf, UInt64[])
    end
    len = ifelse(len == 1, 2, len)
    @inbounds b = buf[1]
    tape = len > div(Mmap.PAGESIZE, 2) ? Mmap.mmap(Vector{UInt64}, len) : Vector{UInt64}(undef, len)
    pos, tapeidx = read!(buf, 1, len, b, tape, 1, Any)
    return getvalue(buf, tape, 1)
end

function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Any})
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
    invalid(InvalidChar, b, Any)
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
        pos += 1
        strlen += 1
        @eof
        @inbounds b = buf[pos]
        if b == UInt8('\\')
            escaped = true
            # skip next character
            pos += 2
            strlen += 2
            @eof
            @inbounds b = buf[pos]
        end
    end
    @inbounds tape[tapeidx] = escaped ? escapedstring(strpos, strlen) : string(strpos, strlen)
    return pos + 1, tapeidx + 1

@label invalid
    invalid(error, b, String)
end

struct True end
@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{True})
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        @inbounds tape[tapeidx] = TRUE
        return pos + 4, tapeidx + 1
    else
        invalid(InvalidChar, b, True)
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
        @inbounds tape[tapeidx] = FALSE
        return pos + 5, tapeidx + 1
    else
        invalid(InvalidChar, b, False)
    end
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Nothing})
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        @inbounds tape[tapeidx] = NULL
        return pos + 4, tapeidx + 1
    else
        invalid(InvalidChar, b, Nothing)
    end
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Object})
    objidx = tapeidx
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8('}')
        @inbounds tape[tapeidx] = object(1)
        tapeidx += 1
        pos += 1
        @goto done
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    tapeidx += 1
    while true
        keypos = pos
        keylen = 0
        # read first key character
        @inbounds b = buf[pos]
        # positioned at first character of object key
        while b != UInt8('"')
            pos += 1
            keylen += 1
            @eof
            @inbounds b = buf[pos]
            if b == UInt8('\\')
                # skip next character
                pos += 2
                keylen += 2
                @eof
                @inbounds b = buf[pos]
            end
        end
        @inbounds tape[tapeidx] = string(keypos, keylen)
        tapeidx += 1
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
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any)
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8('}')
            @inbounds tape[objidx] = object(tapeidx - objidx)
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
    invalid(error, b, Object)
end

@inline function read!(buf::AbstractVector{UInt8}, pos, len, b, tape, tapeidx, ::Type{Array})
    arridx = tapeidx
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8(']')
        @inbounds tape[tapeidx] = array(1)
        tapeidx += 1
        pos += 1
        @goto done
    end
    tapeidx += 1
    while true
        # positioned at start of value
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any)
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8(']')
            @inbounds tape[arridx] = array(tapeidx - arridx)
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
    invalid(error, b, Array)
end

include("strings.jl")
include("show.jl")

end # module

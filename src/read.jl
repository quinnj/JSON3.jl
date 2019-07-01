struct VectorString{T <: AbstractVector{UInt8}} <: AbstractString
    bytes::T
end

Base.ncodeunits(s::VectorString) = length(s.bytes)
Base.codeunit(s::VectorString) = UInt8
Base.length(s::VectorString) = ncodeunits(s)
function Base.codeunit(s::VectorString, i::Int)
    @inbounds b = s.bytes[i]
    return b
end
Base.pointer(v::VectorString) = pointer(v.bytes)
Base.pointer(v::VectorString, i::Integer) = pointer(v.bytes, i)
Base.unsafe_convert(::Type{Ptr{UInt8}}, v::VectorString) = pointer(v)

# high-level user API functions
read(io::IO) = read(Base.read(io, String))
read(bytes::AbstractVector{UInt8}) = read(VectorString(bytes))

function read(str::AbstractString)
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    b = getbyte(buf, pos)
    @wh
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
@label invalid
    invalid(error, buf, pos, Any)
end

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Any}, checkint=true)
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
            if checkint
                int = unsafe_trunc(Int64, float)
                if int == float
                    @inbounds tape[tapeidx] = INT
                    @inbounds tape[tapeidx + 1] = Core.bitcast(UInt64, int)
                else
                    @inbounds tape[tapeidx] = FLOAT
                    @inbounds tape[tapeidx + 1] = Core.bitcast(UInt64, float)
                end
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

function read!(buf, pos, len, b, tape, tapeidx, ::Type{String})
    pos += 1
    @eof
    strpos = pos
    strlen = 0
    escaped = false
    b = getbyte(buf, pos)
    while b != UInt8('"')
        if b == UInt8('\\')
            escaped = true
            # skip next character
            pos += 2
            strlen += 2
        elseif b < UInt8(' ')
            unescaped_control(b)
        else
            pos += 1
            strlen += 1
        end
        @eof
        b = getbyte(buf, pos)
    end
    @inbounds tape[tapeidx] = string(strlen)
    @inbounds tape[tapeidx+1] = ifelse(escaped, ESCAPE_BIT | strpos, strpos)
    return pos + 1, tapeidx + 2

@label invalid
    invalid(error, buf, pos, String)
end

struct True end
function read!(buf, pos, len, b, tape, tapeidx, ::Type{True})
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
function read!(buf, pos, len, b, tape, tapeidx, ::Type{False})
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

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Nothing})
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

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Object})
    objidx = tapeidx
    eT = EMPTY
    pos += 1
    @eof
    b = getbyte(buf, pos)
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
        b = getbyte(buf, pos)
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
            b = getbyte(buf, pos)
        end
        @inbounds tape[tapeidx] = string(keylen)
        @inbounds tape[tapeidx+1] = ifelse(escaped, ESCAPE_BIT | keypos, keypos)
        tapeidx += 2
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        # now positioned at start of value
        prevtapeidx = tapeidx
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any)
        @eof
        b = getbyte(buf, pos)
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
        b = getbyte(buf, pos)
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

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Array})
    arridx = tapeidx
    eT = EMPTY
    pos += 1
    @eof
    b = getbyte(buf, pos)
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
        pos, tapeidx = read!(buf, pos, len, b, tape, tapeidx, Any, eT != FLOAT)
        @eof
        b = getbyte(buf, pos)
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
        b = getbyte(buf, pos)
        @wh
    end

@label done
    return pos, tapeidx
@label invalid
    invalid(error, buf, pos, Array)
end

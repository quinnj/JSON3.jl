# by default, assume json key-values are in right order, and just pass to T constructor
# mutable struct + setfield!
# keyword args constructor
abstract type StructType end
struct Ordered <: StructType end
struct MutableSetField <: StructType end
struct KeywordArgConstrutor <: StructType end
StructType(T) = Ordered()

function read(str::String)
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @inbounds b = buf[pos]
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

function read(str::String, ::Type{T}) where {T}
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        error = UnexpectedEOF
        pos = 0
        @goto invalid
    end
    pos = 1
    @inbounds b = buf[pos]
    @wh
    pos, x = read(StructType(T), buf, pos, len, b, T)
    return x
@label invalid
    invalid(error, buf, pos, T)
end

function read(buf, pos, len, b, U::Union)
    try
        return read(buf, pos, len, b, U.a)
    catch e
        return read(buf, pos, len, b, U.b)
    end
end

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Any})
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

function read(::Ordered, buf, pos, len, b, ::Type{Any})
    if b == UInt8('{')
        return read(Ordered(), buf, pos, len, b, NamedTuple)
    elseif b == UInt8('[')
        return read(Ordered(), buf, pos, len, b, Base.Array)
    elseif b == UInt8('"')
        return read(Ordered(), buf, pos, len, b, String)
    elseif b == UInt8('n')
        return read(Ordered(), buf, pos, len, b, Nothing)
    elseif b == UInt8('t')
        return read(Ordered(), buf, pos, len, b, Bool)
    elseif b == UInt8('f')
        return read(Ordered(), buf, pos, len, b, Bool)
    elseif (UInt8('0') <= b <= UInt8('9')) || b == UInt8('-') || b == UInt8('+')
        float, code, pos = Parsers.typeparser(Float64, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
        if code > 0
            int = unsafe_trunc(Int64, float)
            return pos, ifelse(int == float, int, float)
        end
    end
@label invalid
    invalid(InvalidChar, buf, pos, Any)
end

function read!(buf, pos, len, b, tape, tapeidx, ::Type{String})
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

function read(::Ordered, buf, pos, len, b, ::Type{String})
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
    ptr = pointer(buf, strpos)
    return pos + 1, escaped ? unescape(PointerString(ptr, strlen)) : unsafe_string(ptr, strlen)

@label invalid
    invalid(error, buf, pos, String)
end

function read(::Ordered, buf, pos, len, b, ::Type{Char})
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds x = Char(buf[pos])
    pos += 1
    @eof
    @inbounds b = buf[pos]
    if b != UInt8('"')
        error = InvalidChar
        @goto invalid
    end
    return pos + 1, x

@label invalid
    invalid(error, buf, pos, Char)
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

function read(::Ordered, buf, pos, len, b, ::Type{Bool})
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4, true
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5, false
    else
        invalid(InvalidChar, buf, pos, Bool)
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

function read(::Ordered, buf, pos, len, b, T::Union{Type{Missing}, Type{Nothing}})
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4, T === Missing ? missing : nothing
    else
        invalid(InvalidChar, buf, pos, T)
    end
end

function read(::Ordered, buf, pos, len, b, ::Type{T}) where {T <: Integer}
    int, code, pos = Parsers.typeparser(T, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, int
    end
    invalid(InvalidChar, buf, pos, T)
end

function read(::Ordered, buf, pos, len, b, ::Type{T}) where {T <: AbstractFloat}
    float, code, pos = Parsers.typeparser(T, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, float
    end
    invalid(InvalidChar, buf, pos, T)
end

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Object})
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

function read(::Ordered, buf, pos, len, b, ::Type{NamedTuple})
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8('}')
        return pos + 1, NamedTuple()
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    keys = Symbol[]
    vals = Any[]
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
        push!(keys, escaped ? Symbol(unescape(PointerString(pointer(buf, keypos), keylen))) : _symbol(pointer(buf, keypos), keylen))
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
        pos, y = read(Ordered(), buf, pos, len, b, Any)
        push!(vals, y)
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8('}')
            return pos + 1, NamedTuple{Tuple(keys)}(Tuple(vals))
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

@label invalid
    invalid(error, buf, pos, Object)
end

function read!(buf, pos, len, b, tape, tapeidx, ::Type{Array})
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

function read(::Ordered, buf, pos, len, b, ::Type{A}) where {A <: AbstractArray{T}} where {T}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    vals = A(undef, 0)
    if b == UInt8(']')
        return pos + 1, vals
    end
    while true
        # positioned at start of value
        pos, y = read(StructType(T), buf, pos, len, b, T)
        push!(vals, y)
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8(']')
            return pos + 1, vals
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        @inbounds b = buf[pos]
        @wh
    end

@label invalid
    invalid(error, buf, pos, A)
end

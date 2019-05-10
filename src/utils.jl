_symbol(ptr, len) = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), ptr, len)

macro eof()
    esc(quote
        if pos > len
            error = UnexpectedEOF
            @goto invalid
        end
    end)
end

macro wh()
    esc(quote
        while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
            pos += 1
            if pos > len
                error = UnexpectedEOF
                @goto invalid
            end
            @inbounds b = buf[pos]
        end
    end)
end

const TYPEMASK = 0b1111000000000000000000000000000000000000000000000000000000000000
const OBJECT = UInt64(0)
const ARRAY = UInt64(1) << 60
const STRING = UInt64(2) << 60
const INT = UInt64(3) << 60
const FLOAT = UInt64(4) << 60
const TRUE = UInt64(5) << 60
const FALSE = UInt64(6) << 60
const NULL = UInt64(7) << 60
const ESCAPEDSTRING = UInt64(8) << 60

isobject(x::UInt64) = (x & TYPEMASK) == OBJECT
isarray(x::UInt64) = (x & TYPEMASK) == ARRAY
isstring(x::UInt64) = (x & TYPEMASK) == STRING
isescapedstring(x::UInt64) = (x & TYPEMASK) == ESCAPEDSTRING
isint(x::UInt64) = (x & TYPEMASK) == INT
isfloat(x::UInt64) = (x & TYPEMASK) == FLOAT
istrue(x::UInt64) = (x & TYPEMASK) == TRUE
isfalse(x::UInt64) = (x & TYPEMASK) == FALSE
isnull(x::UInt64) = (x & TYPEMASK) == NULL

object(idx) = UInt64(idx)
array(idx) = UInt64(idx) | ARRAY
string(pos, len) = STRING | (pos << 16) | len
escapedstring(pos, len) = ESCAPEDSTRING | (pos << 16) | len

getidx(x::UInt64) = (x & ~TYPEMASK)
getpos(x::UInt64) = (x & ~TYPEMASK) >> 16
getlen(x::UInt64) = x & 0x000000000000ffff

tapeelements(x::UInt64) = isobject(x) || isarray(x) ? getidx(x) :
                          isint(x) || isfloat(x) ? 2 : 1

@inline function getvalue(buf, tape, tapeidx)
    @inbounds t = tape[tapeidx]
    if isobject(t)
        return Object(buf, tape[tapeidx:tapeidx+getidx(t)])
    elseif isarray(t)
        return Array(buf, tape[tapeidx:tapeidx+getidx(t)])
    elseif isstring(t)
        return unsafe_string(pointer(buf, getpos(t)), getlen(t))
    elseif isescapedstring(t)
        return unescape(PointerString(pointer(buf, getpos(t)), getlen(t)))
    elseif isint(t)
        return Core.bitcast(Int64, tape[tapeidx+1])
    elseif isfloat(t)
        return Core.bitcast(Float64, tape[tapeidx+1])
    elseif istrue(t)
        return true
    elseif isfalse(t)
        return false
    elseif isnull(t)
        return nothing
    end
end

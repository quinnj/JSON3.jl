import StructTypes: StructType, DictType, ArrayType, StringType, NumberType, BoolType, NullType, NoStructType, Struct, Mutable, construct, AbstractType, subtypes, subtypekey

struct RawType <: StructType end

struct RawValue{S}
    bytes::S
    pos::Int
    len::Int
end

function rawbytes end

read(io::IO, ::Type{T}; kw...) where {T} = read(Base.read(io, String), T; kw...)
read(bytes::AbstractVector{UInt8}, ::Type{T}; kw...) where {T} = read(VectorString(bytes), T; kw...)

function _prepare_read(str::AbstractString, ::Type{T}) where {T}
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
    return buf, pos, len, b
@label invalid
    invalid(error, buf, pos, T)
end

function read(str::AbstractString, ::Type{T}; kw...) where {T}
    buf, pos, len, b = _prepare_read(str, T)
    pos, x = read(StructType(T), buf, pos, len, b, T; kw...)
    return x
end

function read!(str::AbstractString, x::T; kw...) where {T}
    buf, pos, len, b = _prepare_read(str, T)
    pos, x = read!(StructType(T), buf, pos, len, b, T, x; kw...)
    return x
end

read(::NoStructType, buf, pos, len, b, ::Type{T}; kw...) where {T} = throw(ArgumentError("$T doesn't have a defined `StructTypes.StructType`"))

function read(::Struct, buf, pos, len, b, U::Union; kw...)
    # Julia implementation detail: Unions are sorted :)
    # This lets us avoid the below try-catch when U <: Union{Missing,T}
    if U.a === Nothing || U.a === Missing
        if buf[pos] == UInt8('n')
            return read(StructType(U.a), buf, pos, len, b, U.a)
        else
            return read(StructType(U.b), buf, pos, len, b, U.b; kw...)
        end
    end
    try
        return read(StructType(U.a), buf, pos, len, b, U.a; kw...)
    catch e
        return read(StructType(U.b), buf, pos, len, b, U.b; kw...)
    end
end

const GLOBAL_IGNORED_TAPE = zeros(UInt64, 1024)

@inline function read(::RawType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    newpos, _ = read!(buf, pos, len, b, GLOBAL_IGNORED_TAPE, 1, Any; kw...)
    return newpos, construct(T, RawValue(buf, pos, newpos - pos))
end

@inline function read(::Struct, buf, pos, len, b, ::Type{Any}; allow_inf::Bool=false, kw...)
    if b == UInt8('{')
        return read(DictType(), buf, pos, len, b, Dict{String, Any}; kw...)
    elseif b == UInt8('[')
        return read(ArrayType(), buf, pos, len, b, Base.Array{Any}; kw...)
    elseif b == UInt8('"')
        return read(StringType(), buf, pos, len, b, String; kw...)
    elseif b == UInt8('n')
        return read(NullType(), buf, pos, len, b, Nothing; kw...)
    elseif b == UInt8('t')
        return read(BoolType(), buf, pos, len, b, Bool; kw...)
    elseif b == UInt8('f')
        return read(BoolType(), buf, pos, len, b, Bool; kw...)
    elseif (UInt8('0') <= b <= UInt8('9')) || b == UInt8('-') || b == UInt8('+') || (allow_inf && (b == UInt8('N') || b == UInt8('I')))
        float, code, pos = Parsers.typeparser(Float64, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
        if code > 0
            int = unsafe_trunc(Int64, float)
            if int == float
                return pos, int
            else
                return pos, float
            end
        end
    end
@label invalid
    invalid(InvalidChar, buf, pos, Any)
end

function read(::StringType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
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
        else
            pos += 1
            strlen += 1
        end
        @eof
        b = getbyte(buf, pos)
    end
    ptr = pointer(buf, strpos)
    return pos + 1, escaped ? construct(T, unescape(PointerString(ptr, strlen)); kw...) : construct(T, ptr, strlen; kw...)

@label invalid
    invalid(error, buf, pos, T)
end

function read(::BoolType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4, construct(T, true; kw...)
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5, construct(T, false; kw...)
    else
        invalid(InvalidChar, buf, pos, Bool)
    end
end

function read(::NullType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4, construct(T, nothing; kw...)
    else
        invalid(InvalidChar, buf, pos, T)
    end
end

function read(::NumberType, buf, pos, len, b, ::Type{T}; parsequoted::Bool=false, kw...) where {T}
    quoted = false
    if parsequoted && b == UInt8('"')
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        quoted = true
    end
    x, code, pos = Parsers.typeparser(StructTypes.numbertype(T), buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if quoted
        b = getbyte(buf, pos)
        @assert b == UInt8('"')
        pos += 1
    end
    if code > 0
        return pos, construct(T, x; kw...)
    end
@label invalid
    invalid(InvalidChar, buf, pos, T)
end

@inline read(::ArrayType, buf, pos, len, b, ::Type{T}; kw...) where {T} = read(ArrayType(), buf, pos, len, b, T, Base.IteratorEltype(T) == Base.HasEltype() ? eltype(T) : Any; kw...)
@inline read(::ArrayType, buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T, eT} = readarray(buf, pos, len, b, T, eT; kw...)
read(::ArrayType, buf, pos, len, b, ::Type{Tuple}, ::Type{eT}; kw...) where {eT} = readarray(buf, pos, len, b, Tuple, eT; kw...)

@inline function readarray(buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T, eT}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    vals = Vector{eT}(undef, 0)
    if b == UInt8(']')
        return pos + 1, construct(T, vals; kw...)
    end
    while true
        # positioned at start of value
        pos, y = read(StructType(eT), buf, pos, len, b, eT; kw...)
        push!(vals, y)
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8(']')
            return pos + 1, construct(T, vals; kw...)
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
    end

@label invalid
    invalid(error, buf, pos, T)
end

mutable struct TupleClosure{T, KW}
    buf::T
    pos::Int
    len::Int
    b::UInt8
    kw::KW
end

@inline function (f::TupleClosure)(i, nm, TT)
    buf, pos, len, b = f.buf, f.pos, f.len, f.b
    pos, x = read(StructType(TT), buf, pos, len, b, TT; f.kw...)
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8(']')
        f.pos = pos + 1
        return x
    elseif b == UInt8(',')
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        f.pos = pos
        f.b = b
        return x
    else
        error = ExpectedComma
        @goto invalid
    end
@label invalid
    invalid(error, buf, pos, TT)
end

@inline function read(::ArrayType, buf, pos, len, b, ::Type{T}, ::Type{eT}; kw...) where {T <: Tuple, eT}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8(']')
        pos += 1
        return pos, T()
    end
    c = TupleClosure(buf, pos, len, b, kw.data)
    x = StructTypes.construct(c, T)

    return c.pos, x
@label invalid
    invalid(error, buf, pos, T)
end

keyvalue(::Type{Symbol}, escaped, ptr, len) = escaped ? Symbol(unescape(PointerString(ptr, len))) : _symbol(ptr, len)
keyvalue(::Type{T}, escaped, ptr, len) where {T} = escaped ? construct(T, unescape(PointerString(ptr, len))) : construct(T, unsafe_string(ptr, len))

@inline read(::DictType, buf, pos, len, b, ::Type{T}; kw...) where {T} = read(DictType(), buf, pos, len, b, T, Symbol, Any; kw...)
@inline read(::DictType, buf, pos, len, b, ::Type{T}; kw...) where {T <: NamedTuple} = read(DictType(), buf, pos, len, b, T, Symbol, Any; kw...)
@inline read(::DictType, buf, pos, len, b, ::Type{Dict}; kw...) = read(DictType(), buf, pos, len, b, Dict, String, Any; kw...)
@inline read(::DictType, buf, pos, len, b, ::Type{T}; kw...) where {T <: AbstractDict} = read(DictType(), buf, pos, len, b, T, keytype(T), valtype(T); kw...)

@inline function read(::DictType, buf, pos, len, b, ::Type{T}, ::Type{K}, ::Type{V}; kw...) where {T, K, V}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    x = Dict{K, V}()
    if b == UInt8('}')
        return pos + 1, construct(T, x; kw...)
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
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
        key = keyvalue(K, escaped, pointer(buf, keypos), keylen)
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
        pos, y = read(StructType(V), buf, pos, len, b, V; kw...)
        x[key] = y
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            return pos + 1, construct(T, x; kw...)
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

@label invalid
    invalid(error, buf, pos, Object)
end

mutable struct MutableClosure{T, KW}
    buf::T
    pos::Int
    len::Int
    b::UInt8
    kw::KW
end

@inline function (f::MutableClosure)(i, nm, TT; kw...)
    kw2 = merge(kw.data, f.kw)
    pos_i, y_i = read(StructType(TT), f.buf, f.pos, f.len, f.b, TT; kw2...)
    f.pos = pos_i
    return y_i
end

@inline function read(::Mutable, buf, pos, len, b, ::Type{T}; kw...) where {T}
    x = T()
    pos, x = read!(Mutable(), buf, pos, len, b, T, x; kw...)
    return pos, x
end

@inline function read!(::Any, buf, pos, len, b, ::Type{T}, x::T; kw...) where {T}
    throw(ArgumentError("read! is only defined when T is of the `Mutable` struct type"))
end

@inline function read!(::Mutable, buf, pos, len, b, ::Type{T}, x::T; kw...) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        pos += 1
        return pos, x
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    while true
        keypos = pos
        keylen = 0
        escaped = false
        b = getbyte(buf, pos)
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
        key = keyvalue(Symbol, escaped, pointer(buf, keypos), keylen)
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
        c = MutableClosure(buf, pos, len, b, kw.data)
        if StructTypes.applyfield!(c, x, key)
            pos = c.pos
        else
            pos, _ = read(Struct(), buf, pos, len, b, Any)
        end
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            pos += 1
            return pos, x
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

@label invalid
    invalid(error, buf, pos, T)
end

mutable struct StructClosure{T, KW}
    buf::T
    pos::Int
    len::Int
    kw::KW
end

@inline function (f::StructClosure)(i, nm, TT)
    pos_i, x_i = readvalue(f.buf, f.pos, f.len, TT; f.kw...)
    f.pos = pos_i
    return x_i
end

@inline function read(::Struct, buf, pos, len, b, ::Type{T}; kw...) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        pos += 1
        return pos, T()
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    c = StructClosure(buf, pos, len, kw.data)
    x = StructTypes.construct(c, T)
    return c.pos, x

@label invalid
    invalid(error, buf, pos, T)
end

@inline function readvalue(buf, pos, len, ::Type{T}; kw...) where {T}
    b = getbyte(buf, pos)
    while b != UInt8('"')
        pos += ifelse(b == UInt8('\\'), 2, 1)
        @eof
        b = getbyte(buf, pos)
    end
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
    # read value
    pos, y = read(StructType(T), buf, pos, len, b, T; kw...)
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        pos += 1
        return pos, y
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
    return pos, y
@label invalid
    invalid(error, buf, pos, T)
end

@inline function read(::AbstractType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    types = subtypes(T)
    if length(types) == 1
        only_subtype = types[1]
        return read(StructType(only_subtype), buf, pos, len, b, only_subtype; kw...)
    end
    return _read(AbstractType(), buf, pos, len, b, T; kw...)
end

@inline function _read(::AbstractType, buf, pos, len, b, ::Type{T}; kw...) where {T}
    startpos = pos
    startb = b
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    b = getbyte(buf, pos)
    @wh
    if b == UInt8('}')
        throw(ArgumentError("invalid json abstract type"))
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    types = subtypes(T)
    skey = subtypekey(T)
    while true
        keypos = pos
        keylen = 0
        escaped = false
        b = getbyte(buf, pos)
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
        key = keyvalue(Symbol, escaped, pointer(buf, keypos), keylen)
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
        # read value
        pos, val = read(Struct(), buf, pos, len, b, Any)
        if key == skey
            TT = types[Symbol(val)]
            return read(StructType(TT), buf, startpos, len, startb, TT; kw...)
        end
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            pos += 1
            throw(ArgumentError("invalid json abstract type: didn't find subtypekey"))
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

@label invalid
    invalid(error, buf, pos, T)
end

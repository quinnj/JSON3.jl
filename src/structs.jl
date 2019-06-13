abstract type StructType end

# "Data" type: fields are json keys, field values are json values; use names, omitempties, excludes
abstract type DataType <: StructType end
struct Struct <: DataType end
struct Mutable <: DataType end

StructType(::Type{T}) where {T} = Struct()
StructType(x::T) where {T} = StructType(T)
# maps Julia struct field name to json key name: ((:field1, :json1), (:field2, :json2))
names(x::T) where {T} = names(T)
names(::Type{T}) where {T} = ()

Base.@pure function julianame(names::Tuple{Vararg{Tuple{Symbol, Symbol}}}, jsonname::Symbol)
    for nm in names
        nm[2] === jsonname && return nm[2]
    end
    return jsonname
end

Base.@pure function jsonname(names::Tuple{Vararg{Tuple{Symbol, Symbol}}}, julianame::Symbol)
    for nm in names
        nm[1] === julianame && return nm[1]
    end
    return julianame
end

# Julia struct field names as symbols that will be ignored when reading, and never written
excludes(x::T) where {T} = excludes(T)
excludes(::Type{T}) where {T} = ()
# Julia struct field names as symbols 
omitempties(x::T) where {T} = omitempties(T)
omitempties(::Type{T}) where {T} = ()

# "interface" type: fields are internal, json representation is accessible via transform/interface functions
abstract type JSONType end
struct ObjectType <: JSONType end
struct ArrayType <: JSONType end
struct StringType <: JSONType end
struct NumberType <: JSONType end
struct BoolType <: JSONType end
struct NullType <: JSONType end

# "abstract" type: json representation via a concrete subtype, json includes subtype key-value to signal concrete subtype
struct AbstractType <: StructType end

subtypekey(x::T) where {T} = subtypekey(T)
subtypekey(::Type{T}) where {T} = :type
subtypes(x::T) where {T} = subtypes(T)
subtypes(::Type{T}) where {T} = NamedTuple()

read(io::IO, ::Type{T}) where {T} = read(Base.read(io, String), T)
read(bytes::Vector{UInt8}, ::Type{T}) where {T} = read(String(bytes), T)

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

function read(::Struct, buf, pos, len, b, U::Union)
    try
        return read(StructType(U.a), buf, pos, len, b, U.a)
    catch e
        return read(StructType(U.b), buf, pos, len, b, U.b)
    end
end

function read(::Struct, buf, pos, len, b, ::Type{Any})
    if b == UInt8('{')
        return read(ObjectType(), buf, pos, len, b, Dict{Symbol, Any})
    elseif b == UInt8('[')
        return read(ArrayType(), buf, pos, len, b, Base.Array{Any})
    elseif b == UInt8('"')
        return read(StringType(), buf, pos, len, b, String)
    elseif b == UInt8('n')
        return read(NullType(), buf, pos, len, b, Nothing)
    elseif b == UInt8('t')
        return read(BoolType(), buf, pos, len, b, Bool)
    elseif b == UInt8('f')
        return read(BoolType(), buf, pos, len, b, Bool)
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

StructType(::Type{<:AbstractString}) = StringType()
StructType(::Type{<:Enum}) = StringType()
StructType(::Type{DataType}) = StringType()

# argh!
function (::Type{E})(str::String) where {E <: Enum}
    sym = Symbol(str)
    for (k, v) in Base.Enums.namemap(E)
        sym == v && return E(k)
    end
    throw(ArgumentError("invalid $E string value: \"$str\""))
end

function read(::StringType, buf, pos, len, b, ::Type{T}) where {T}
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
    return pos + 1, escaped ? T(unescape(PointerString(ptr, strlen))) : T(unsafe_string(ptr, strlen))

@label invalid
    invalid(error, buf, pos, String)
end

StructType(::Type{Char}) = StringType()

function read(::StringType, buf, pos, len, b, ::Type{Char})
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

StructType(::Type{Bool}) = BoolType()

function read(::BoolType, buf, pos, len, b, ::Type{T}) where {T}
    if pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4, T(true)
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5, T(false)
    else
        invalid(InvalidChar, buf, pos, Bool)
    end
end

StructType(::Type{Nothing}) = NullType()
StructType(::Type{Missing}) = NullType()

function read(::NullType, buf, pos, len, b, ::Type{T}) where {T}
    if pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4, T()
    else
        invalid(InvalidChar, buf, pos, T)
    end
end

StructType(::Type{<:Integer}) = NumberType()

function read(::NumberType, buf, pos, len, b, ::Type{T}) where {T <: Integer}
    int, code, pos = Parsers.typeparser(T, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, int
    end
    invalid(InvalidChar, buf, pos, T)
end

StructType(::Type{<:AbstractFloat}) = NumberType()
numbertype(x::T) where {T <: Real} = T
numbertype(x) = Float64

function read(::NumberType, buf, pos, len, b, ::Type{T}) where {T}
    x, code, pos = Parsers.typeparser(numbertype(T), buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, T(x)
    end
    invalid(InvalidChar, buf, pos, T)
end

StructType(::Type{<:AbstractArray}) = ArrayType()
StructType(::Type{<:AbstractSet}) = ArrayType()
StructType(::Type{<:Tuple}) = ArrayType()

read(::ArrayType, buf, pos, len, b, ::Type{T}) where {T} = read(ArrayType(), buf, pos, len, b, T, Base.IteratorEltype(T) == Base.HasEltype() ? eltype(T) : Any)
function read(::ArrayType, buf, pos, len, b, ::Type{T}, ::Type{eT}) where {T, eT}
    if b != UInt8('[')
        error = ExpectedOpeningArrayChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    vals = Vector{eT}(undef, 0)
    if b == UInt8(']')
        return pos + 1, T(vals)
    end
    while true
        # positioned at start of value
        pos, y = read(StructType(eT), buf, pos, len, b, eT)
        push!(vals, y)
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8(']')
            return pos + 1, T(vals)
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
    invalid(error, buf, pos, T)
end

StructType(::Type{<:AbstractDict}) = ObjectType()

read(::ObjectType, buf, pos, len, b, ::Type{T}) where {T <: AbstractDict} = read(ObjectType(), buf, pos, len, b, T, keytype(T), valtype(T))
function read(::ObjectType, buf, pos, len, b, ::Type{T}, ::Type{K}=Any, ::Type{V}=Any) where {T, K, V}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    x = T()
    if b == UInt8('}')
        return pos + 1, x
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
        key = escaped ? unescape(PointerString(pointer(buf, keypos), keylen)) : unsafe_string(pointer(buf, keypos), keylen)
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
        pos, y = read(StructType(V), buf, pos, len, b, V)
        x[K(key)] = y
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8('}')
            return pos + 1, x
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

@inline function read(::Mutable, buf, pos, len, b, ::Type{T}) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    x = T()
    if b == UInt8('}')
        pos += 1
        return pos, x
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    nms = names(T)
    excl = excludes(T)
    pos += 1
    @eof
    while true
        keypos = pos
        keylen = 0
        escaped = false
        @inbounds b = buf[pos]
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
        key = escaped ? Symbol(unescape(PointerString(pointer(buf, keypos), keylen))) : _symbol(pointer(buf, keypos), keylen)
        key = julianame(nms, key)
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
        # read value
        ind = Base.fieldindex(T, key, false)
        if ind > 0
            FT = fieldtype(T, key)
            pos, y = read(StructType(FT), buf, pos, len, b, FT)
            if !symbolin(excl, key)
                setfield!(x, key, y)
            end
        else
            # read the unknown key's value, but ignore it
            pos, _ = read(Struct(), buf, pos, len, b, Any)
        end
        @eof
        @inbounds b = buf[pos]
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
    invalid(error, buf, pos, T)
end

@inline function read(::Struct, buf, pos, len, b, ::Type{T}) where {T}
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
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
    N = fieldcount(T)
    Base.@nexprs 32 i -> begin
        pos, x_i = readvalue(buf, pos, len, fieldtype(T, i))
        if N == i
            return pos, Base.@ncall i T x
        end
    end
    vals = []
    for i = 33:N
        pos, y = readvalue(buf, pos, len, fieldtype(T, i))
        push!(vals, y)
    end
    return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16,
                  x17, x18, x19, x20, x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31, x32, vals...)

@label invalid
    invalid(error, buf, pos, T)
end

@inline function readvalue(buf, pos, len, ::Type{T}) where {T}
    @inbounds b = buf[pos]
    while b != UInt8('"')
        pos += ifelse(b == UInt8('\\'), 2, 1)
        @eof
        @inbounds b = buf[pos]
    end
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
    # read value
    pos, y = read(StructType(T), buf, pos, len, b, T)
    @eof
    @inbounds b = buf[pos]
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
    @inbounds b = buf[pos]
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

@inline function read(::AbstractType, buf, pos, len, b, ::Type{T}) where {T}
    startpos = pos
    startb = b
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
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
        @inbounds b = buf[pos]
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
        key = escaped ? Symbol(unescape(PointerString(pointer(buf, keypos), keylen))) : _symbol(pointer(buf, keypos), keylen)
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
        # read value
        pos, val = read(Struct(), buf, pos, len, b, Any)
        if key == skey
            TT = types[Symbol(val)]
            return read(StructType(TT), buf, startpos, len, startb, TT)
        end
        @eof
        @inbounds b = buf[pos]
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
    invalid(error, buf, pos, T)
end
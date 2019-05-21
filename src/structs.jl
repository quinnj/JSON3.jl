@inline function read(::MutableSetField, buf, pos, len, b, ::Type{T}) where {T}
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
        key = get(nms, key, key)
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
            if !get(excl, key, false)
                setfield!(x, key, y)
            end
        else
            # read the unknown key's value, but ignore it
            pos, _ = read(Ordered(), buf, pos, len, b, Any)
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

@inline function read(::Ordered, buf, pos, len, b, ::Type{T}) where {T}
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
    pos, x1 = readvalue(buf, pos, len, fieldtype(T, 1))
    if fieldcount(T) == 1
        return pos, T(x1)
    end
    pos, x2 = readvalue(buf, pos, len, fieldtype(T, 2))
    if fieldcount(T) == 2
        return pos, T(x1, x2)
    end
    pos, x3 = readvalue(buf, pos, len, fieldtype(T, 3))
    if fieldcount(T) == 3
        return pos, T(x1, x2, x3)
    end
    pos, x4 = readvalue(buf, pos, len, fieldtype(T, 4))
    if fieldcount(T) == 4
        return pos, T(x1, x2, x3, x4)
    end
    pos, x5 = readvalue(buf, pos, len, fieldtype(T, 5))
    if fieldcount(T) == 5
        return pos, T(x1, x2, x3, x4, x5)
    end
    pos, x6 = readvalue(buf, pos, len, fieldtype(T, 6))
    if fieldcount(T) == 6
        return pos, T(x1, x2, x3, x4, x5, x6)
    end
    pos, x7 = readvalue(buf, pos, len, fieldtype(T, 7))
    if fieldcount(T) == 7
        return pos, T(x1, x2, x3, x4, x5, x6, x7)
    end
    pos, x8 = readvalue(buf, pos, len, fieldtype(T, 8))
    if fieldcount(T) == 8
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8)
    end
    pos, x9 = readvalue(buf, pos, len, fieldtype(T, 9))
    if fieldcount(T) == 9
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9)
    end
    pos, x10 = readvalue(buf, pos, len, fieldtype(T, 10))
    if fieldcount(T) == 10
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10)
    end
    pos, x11 = readvalue(buf, pos, len, fieldtype(T, 11))
    if fieldcount(T) == 11
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11)
    end
    pos, x12 = readvalue(buf, pos, len, fieldtype(T, 12))
    if fieldcount(T) == 12
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12)
    end
    pos, x13 = readvalue(buf, pos, len, fieldtype(T, 13))
    if fieldcount(T) == 13
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13)
    end
    pos, x14 = readvalue(buf, pos, len, fieldtype(T, 14))
    if fieldcount(T) == 14
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14)
    end
    pos, x15 = readvalue(buf, pos, len, fieldtype(T, 15))
    if fieldcount(T) == 15
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15)
    end
    pos, x16 = readvalue(buf, pos, len, fieldtype(T, 16))
    if fieldcount(T) == 16
        return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16)
    end
    vals = []
    for i = 17:fieldcount(T)
        pos, y = readvalue(buf, pos, len, fieldtype(T, i))
        push!(vals, y)
    end
    return pos, T(x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, vals...)

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

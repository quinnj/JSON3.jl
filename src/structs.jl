# by default, assume json key-values are in right order, and just pass to T constructor
# mutable struct + setfield!
# keyword args constructor
abstract type StructType end
struct Ordered <: StructType end
struct MutableSetField <: StructType end
struct KeywordArgConstrutor <: StructType end
StructType(T) = Ordered()

function read(buf, pos, len, b, ::Type{T}) where {T <: Integer}
    int, code, pos = Parsers.typeparser(Int64, buf, pos, len, b, Int16(0), Parsers.OPTIONS)
    if code > 0
        return pos, int
    end
    invalid(InvalidChar, buf, pos, T)
end

function read(str::String, ::Type{T}) where {T}
    buf = codeunits(str)
    len = length(buf)
    error = InvalidChar
    pos = 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    pos += 1
    @eof
    @inbounds b = buf[pos]
    @wh
    if b == UInt8('}')
        x = T()
        pos += 1
        @goto done
    elseif b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    @eof
    x = T((ntuple(fieldcount(T)) do i
        @inbounds b = buf[pos]
        while b != UInt8('"')
            if b == UInt8('\\')
                pos += 2
            else
                pos += 1
            end
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
        pos, y = read(buf, pos, len, b, fieldtype(T, i))
        @eof
        @inbounds b = buf[pos]
        @wh
        if b == UInt8('}')
            pos += 1
            return y
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
        return y
        @label invalid
            invalid(error, buf, pos, T)
    end)...)

@label done
    return pos, x
@label invalid
    invalid(error, buf, pos, T)
end


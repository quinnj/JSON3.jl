using Parsers
using StructTypes

export StringNumber

struct StringNumber
    value::String
end

@inline StructTypes.StructType(::Type{StringNumber}) = StructTypes.NumberType()
@inline StructTypes.numbertype(::Type{StringNumber}) = StringNumber

@inline function Base.getindex(x::StringNumber)
    result = x.value::String
    return result
end

@inline function _is_part_of_number(x::UInt8)
    return (x == 0x2c) || (x == 0x2e) || (0x30 <= x <= 0x39)
end

@inline function Parsers.typeparser(::Type{T},
                                    source,
                                    pos,
                                    len,
                                    b,
                                    code,
                                    options::Parsers.Options) where T <: StringNumber
    chars = Char[]
    @assert len == length(source)
    @assert pos < len
    @assert _is_part_of_number(b)
    while true
        push!(chars, Char(b))
        if pos == len
            break
        end
        pos += 1
        b = getbyte(source, pos)
        if !_is_part_of_number(b)
            break
        end
    end
    x = join(chars)
    code = Parsers.OK
    return x, code, pos
end

@inline function JSON3.write(::StructTypes.NumberType,
                             buf,
                             pos,
                             len,
                             x::StringNumber;
                             kw...)
    value = Base.getindex(x)::String
    bytes = codeunits(value)
    sz = sizeof(bytes)
    @check sz
    for i = 1:sz
        @inbounds @writechar bytes[i]
    end
    return buf, pos, len
end

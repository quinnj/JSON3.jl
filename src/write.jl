@noinline function realloc!(buf, len)
    new = Mmap.mmap(Vector{UInt8}, trunc(Int, len * 1.25))
    return new, length(new)
end

macro writechar(chars...)
    block = quote
        if (pos + $(length(chars) - 1) > len
            buf, len = realloc!(buf, len)
        end
    end
    for c in chars
        push!(block.args, quote
            @inbounds buf[pos] = UInt8($c)
            pos += 1
        end)
    end
    return block
end

function write(buf, pos, len, x::T) where {T <: AbstractDict}
    @writechar '{'
    n = length(x)
    i = 1
    for (k, v) in obj
        buf, pos = write(buf, pos, len, string(k))
        @writechar ':'
        buf, pos = write(buf, pos, len, v)
        if i < n
            @writechar ','
        end
        i += 1
    end

@label done
    @writechar '}'
    return buf, pos
end

function write(buf, pos, len, x::T) where {T <: Union{AbstractArray, AbstractSet, Tuple}}
    @writechar '['
    n = length(x)
    i = 1
    for y in x
        buf, pos = write(buf, pos, len, y)
        if i < n
            @writechar ','
        end
        i += 1
    end
    @writechar ']'
    return buf, pos
end

function write(buf, pos, len, x::Union{Nothing, Missing})
    @writechar 'n' 'u' 'l' 'l'
    return buf, pos
end

function write(buf, pos, len, x::Bool)
    if x
        @writechar 't' 'r' 'u' 'e'
    else
        @writechar 'f' 'a' 'l' 's' 'e'
    end
    return buf, pos
end

function write(buf, pos, len, x::Number)

end

"""
    JSON3.@pretty json_str

Pretty print a JSON string or an object as JSON.
"""
macro pretty(json)
    return esc(:(JSON3.pretty($json)))
end

"""
    JSON3.pretty(x; kw...)
    JSON3.pretty(io, x; kw...)

Pretty print a JSON string.

## Args

* `x`: A JSON string, or an object to write to JSON then pretty print.
* `io`: The `IO` object to write the pretty printed string to. [default `stdout`]

## Keyword Args

See [`JSON3.write`](@ref) and [`JSON3.read`](@ref).
"""
pretty(str; kw...) = pretty(stdout, str; kw...)
pretty(out::IO, x; kw...) = pretty(out, JSON3.write(x; kw...); kw...)
function pretty(out::IO, str::String, indent=0, offset=0; kw...)
    buf = codeunits(str)
    len = length(buf)
    if len == 0
        return
    end
    pos = 1
    b = getbyte(buf, pos)
    @wh
    # printing object?
    if b == UInt8('{')
        Base.write(out, b)
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8('}')
            Base.write(out, b)
            return
        end
        Base.write(out, '\n')
        indent += 1
        keys = []
        vals = []
        # loop thru all key-value pairs, keeping track of longest key to pad others
        while b != UInt8('}')
            pos, str = JSON3.read(StructTypes.StringType(), buf, pos, len, b, String; kw...)
            push!(keys, str)
            @eof
            b = getbyte(buf, pos) # ':'
            @wh
            pos += 1
            @eof
            b = getbyte(buf, pos)
            @wh
            pos, x = JSON3.read(StructTypes.Struct(), buf, pos, len, b, Any; kw...)
            push!(vals, x)
            @eof
            b = getbyte(buf, pos) # ',' or '}'
            @wh
            if b == UInt8('}')
                break
            end
            pos += 1
            @eof
            b = getbyte(buf, pos)
            @wh
        end
        maxlen = maximum(map(sizeof, keys)) + 5
        # @show maxlen
        for i = 1:length(keys)
            Base.write(out, "  "^indent)
            Base.write(out, lpad("\"$(keys[i])\"" * ": ", maxlen + offset, ' '))
            pretty(out, JSON3.write(vals[i]; kw...), indent, maxlen + offset; kw...)
            if i == length(keys)
                indent -= 1
                Base.write(out, "\n" * ("  "^indent * " "^offset) * "}")
            else
                Base.write(out, ",\n")
            end
        end

    # printing array?
    elseif b == UInt8('[')
        Base.write(out, b)
        pos += 1
        @eof
        b = getbyte(buf, pos)
        @wh
        if b == UInt8(']')
            Base.write(out, b)
            return
        end
        Base.write(out, '\n')
        indent += 1
        vals = []
        while b != UInt8(']')
            pos, x = JSON3.read(StructTypes.Struct(), buf, pos, len, b, Any; kw...)
            push!(vals, x)
            @eof
            b = getbyte(buf, pos) # ',' or ']'
            @wh
            if b == UInt8(']')
                break
            end
            pos += 1
            @eof
            b = getbyte(buf, pos)
            @wh
        end
        for (i, val) in enumerate(vals)
            Base.write(out, "  "^indent * " "^offset)
            pretty(out, JSON3.write(vals[i]; kw...), indent, offset; kw...)
            if i == length(vals)
                indent -= 1
                Base.write(out, "\n" * ("  "^indent * " "^offset) * "]")
            else
                Base.write(out, ",\n")
            end
        end

    # printing constant?
    else
        Base.write(out, str)
    end
    return
@label invalid
    Base.error("error pretty-fying json: $error")
end
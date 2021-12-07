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
        Base.write(out, "{\n")

        obj = JSON3.read(str; kw...)

        if length(obj) == 0
            Base.write(out, "}")
            return
        end

        ks = collect(keys(obj))
        maxlen = maximum(map(sizeof, ks)) + 5
        indent += 1

        i = 1
        for (key, value) in obj
            Base.write(out, "  "^indent)
            Base.write(out, lpad("\"$(key)\"" * ": ", maxlen + offset, ' '))
            pretty(out, JSON3.write(value; kw...), indent, maxlen + offset; kw...)
            if i == length(obj)
                indent -= 1
                Base.write(out, "\n" * ("  "^indent * " "^offset) * "}")
            else
                Base.write(out, ",\n")
                i += 1
            end
        end
    # printing array?
    elseif b == UInt8('[')
        Base.write(out, "[\n")

        arr = JSON3.read(str; kw...)

        if length(arr) == 0
            Base.write(out, "]")
            return
        end

        indent += 1

        for (i, val) in enumerate(arr)
            Base.write(out, "  "^indent * " "^offset)
            pretty(out, JSON3.write(val; kw...), indent, offset; kw...)
            if i == length(arr)
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

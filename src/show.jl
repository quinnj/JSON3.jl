Base.show(io::IO, j::Object) = _show(io, j)
Base.show(io::IO, j::Array) = _show(io, j)
_show(io::IO, x, indent=0, offset=0) = show(io, x)

function _show(io::IO, obj::Object, indent=0, offset=0)
    tape = gettape(obj)
    buf = getbuf(obj)
    if getidx(tape[1]) == 1
        print(io, "{}")
        return
    end
    println(io, "{")
    indent += 1
    keys = []
    vals = []
    # loop thru all key-value pairs, keeping track of longest key to pad others
    tapeidx = 2
    last = getidx(tape[1])
    while tapeidx <= last
        t = tape[tapeidx]
        push!(keys, unsafe_string(pointer(buf, getpos(t)), getlen(t)))
        tapeidx += 1
        push!(vals, getvalue(buf, tape, tapeidx))
        @inbounds tapeidx += tapeelements(tape[tapeidx])
    end
    maxlen = maximum(map(length, keys)) + 5
    # @show maxlen
    for i = 1:length(keys)
        Base.write(io, "  "^indent)
        Base.write(io, lpad("\"$(keys[i])\"" * ": ", maxlen + offset, ' '))
        _show(io, vals[i], indent, maxlen + offset)
        if i == length(keys)
            indent -= 1
            Base.write(io, "\n" * ("  "^indent * " "^offset) * "}")
        else
            Base.write(io, ",\n")
        end
    end
    return
end

function _show(io::IO, arr::Array, indent=0, offset=0)
    tape = gettape(arr)
    buf = getbuf(arr)
    if getidx(tape[1]) == 1
        print(io, "[]")
        return
    end
    println(io, "[")
    indent += 1
    vals = []
    tapeidx = 2
    last = getidx(tape[1])
    while tapeidx <= last
        push!(vals, getvalue(buf, tape, tapeidx))
        @inbounds tapeidx += tapeelements(tape[tapeidx])
    end
    for (i, val) in enumerate(vals)
        Base.write(io, "  "^indent * " "^offset)
        _show(io, vals[i], indent, offset)
        if i == length(vals)
            indent -= 1
            Base.write(io, "\n" * ("  "^indent * " "^offset) * "]")
        else
            Base.write(io, ",\n")
        end
    end
    return
end

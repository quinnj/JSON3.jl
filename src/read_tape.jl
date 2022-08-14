struct Cursor
    cursor::Int
end
Base.convert(::Type{T}, x::Cursor) where {T<:Integer} = convert(T, x.cursor)
Base.convert(::Type{Cursor}, x::T) where {T<:Integer} = Cursor(x)
Base.:+(c::Cursor, i::Integer) = Cursor(c.cursor+i)
Base.:-(c::Cursor, i::Integer) = Cursor(c.cursor-i)
Base.to_index(c::Cursor) = c.cursor
Base.isless(c1::Cursor, c2::Cursor) = isless(c1.cursor, c2.cursor)

struct Reader
    tape::Vector{UInt64}
end

Reader() = Reader(
    Vector{UInt64}(),
)

struct JSONItem{S}
    parser::Reader
    str::S
    cursor::Cursor
end

gettape(x::JSONItem) = x.parser.tape

function parse!(parser::Reader, str; jsonlines::Bool=false, kw...)
    buf = codeunits(str)
    tape = parser.tape
    len = length(buf)
    tapesize = len < 1000 ? len + 4 : div(len, 10)
    resize!(tape, tapesize)
    pos = 1
    b = getbyte(buf, pos)
    if jsonlines
        pos, tapeidx = jsonlines!(buf, pos, len, b, tape, Int64(1); kw...)
    else
        pos, tapeidx = read!(buf, pos, len, b, tape, Int64(1), Any; kw...)
    end
    JSONItem(parser, str, Cursor(1))
end

function parse!(parser::Reader, str, ::Type{T}) where {T}
    item = parse!(parser, str)
    as(item, T)
end

@inline function gettypemask(x::JSONItem)
    @inbounds gettape(x)[x.cursor] & TYPEMASK
end

empty(x::JSONItem) = gettypemask(x) == EMPTY
isany(x::JSONItem) = gettypemask(x) == ANY
isobject(x::JSONItem) = gettypemask(x) == OBJECT
isarray(x::JSONItem) = gettypemask(x) == ARRAY
isstring(x::JSONItem) = gettypemask(x) == STRING
isint(x::JSONItem) = gettypemask(x) == INT
isfloat(x::JSONItem) = gettypemask(x) == FLOAT
isbool(x::JSONItem) = gettypemask(x) == BOOL
isnull(x::JSONItem) = gettypemask(x) == NULL
isintfloat(x::JSONItem) = gettypemask(x) == (INT | FLOAT)
nonnull(x::JSONItem) = gettypemask(x) & ~NULL

struct JSONField{S}
    parser::Reader
    str::S
    cursor::Cursor
end

@inline function key(field::JSONField)
    JSONItem(
        field.parser,
        field.str,
        field.cursor
    ) |> asstring
end

@inline function value(field::JSONField)
    JSONItem(
        field.parser,
        field.str,
        field.cursor + 2
    )
end

@inline function value(field::JSONField, ::Type{T}) where {T}
    as(value(field), T)
end

struct JSONObject{S}
    parser::Reader
    str::S
    cursor::Cursor
    nfields::Int
    maxcursor::Cursor
end

@inline Base.length(x::JSONObject) = x.nfields
@inline Base.isempty(x::JSONObject) = length(x) == 0

@inline function next(x::JSONObject, cursor::Union{Nothing,Cursor}=nothing)
    if isnothing(cursor)
        isempty(x) ? nothing : x.cursor
    else
        cursor += 2 # jumping over the key
        u = x.parser.tape[cursor]
        cursor += isobject(u) | isarray(u) ? getnontypemask(u) : 2
        cursor > x.maxcursor ? nothing : cursor
    end
end

function tryfindcursor(x::JSONObject, key_::AbstractString, default, start::Union{Nothing, Cursor}=nothing)
    cursor = next(x, start)
    while cursor !== nothing
        field = getpair(x, cursor)
        key(field) == key_ && return value(field).cursor
        cursor = next(x, cursor)
    end
    default
end

function findcursor(x::JSONObject, key_::AbstractString, start::Union{Nothing, Cursor}=nothing)
    cursor = next(x, start)
    while cursor !== nothing
        field = getpair(x, cursor)
        key(field) == key_ && return value(field).cursor
        cursor = next(x, cursor)
    end
    throw(KeyError(key_)) # this allows for type stability optimizations
end

function Base.iterate(x::JSONObject)
    cursor = next(x)
    getpair(x, cursor), cursor
end

function Base.iterate(x::JSONObject, cursor::Cursor)
    cursor = next(x, cursor)
    isnothing(cursor) ? nothing : (getpair(x, cursor), cursor)
end

@inline function getpair(x::JSONObject, cursor::Cursor)
    JSONField(
        x.parser,
        x.str,
        cursor,
    )
end

function Base.getindex(x::JSONObject, key::AbstractString, ::Type{T}=Any, start::Union{Nothing, Cursor}=nothing) where {T}
    cursor = findcursor(x, key, start)
    x[cursor, T]
end

@inline function Base.getindex(x::JSONObject, cursor_onvalue::Cursor, ::Type{T}=Any) where {T}
    item = JSONItem(
        x.parser,
        x.str,
        cursor_onvalue,
    )
    as(item, T)
end

struct JSONArray{T,S}
    parser::Reader
    str::S
    cursor::Cursor
    nfields::Int
    maxcursor::Cursor
end

@inline Base.length(x::JSONArray) = x.nfields
@inline Base.isempty(x::JSONArray) = length(x) == 0
@inline Base.eltype(::JSONArray{T}) where {T} = T
@inline Base.eltype(::JSONArray{Any}) = JSONItem

@inline function next(x::JSONArray)
    isempty(x) ? nothing : x.cursor
end

@inline function next(x::JSONArray{T}, cursor::Cursor) where {T}
    if issmalltype(geteltype(T))
        cursor += 2
    else
        @inbounds u = x.parser.tape[cursor]
        cursor += isobject(u) | isarray(u) ? getnontypemask(u) : 2
    end
    cursor > x.maxcursor ? nothing : cursor
end

function Base.iterate(x::JSONArray)
    cursor = next(x)
    isnothing(cursor) ? nothing : (x[cursor], cursor)
end

function Base.iterate(x::JSONArray{T}, cursor::Cursor) where {T}
    cursor = next(x, cursor)
    isnothing(cursor) ? nothing : (x[cursor], cursor)
end

@inline function Base.getindex(x::JSONArray{T}, cursor::Cursor) where {T}
    item = JSONItem(
        x.parser,
        x.str,
        cursor,
    )
    as(item, T)
end

@inline as(item::JSONItem, ::Type{Any}) = item
@inline as(item::JSONItem, ::Type{T}) where {T<:AbstractString} = asstring(item)
@inline as(item::JSONItem, ::Type{T}) where {T<:Integer} = convert(T, asint(item))
@inline as(item::JSONItem, ::Type{T}) where {T<:AbstractFloat} = convert(T, asfloat(item))
@inline as(item::JSONItem, ::Type{Bool}) = asbool(item)
@inline as(item::JSONItem, ::Type{<:JSONArray})= asarray(item, Any)
@inline as(item::JSONItem, ::Type{<:JSONArray{T}}) where {T} = asarray(item, T)
@inline as(item::JSONItem, ::Type{<:JSONObject}) = asobject(item)

@inline function asobject(x::JSONItem)
    @assert isobject(x)
    tape = gettape(x)
    @inbounds JSONObject(
        x.parser,
        x.str,
        x.cursor+2,
        getlen(tape[x.cursor+1]),
        x.cursor + getlen(tape[x.cursor])-1,
    )
end

@inline function asarray(x::JSONItem, ::Type{T}) where {T}
    @assert isarray(x)
    tape = gettape(x)
    # type = tape[x.cursor+1] |> gettypemask
    # todo: make this work
    # @assert (type == EMPTY) || T==Any || (type == geteltype(T))
    @inbounds JSONArray{T, typeof(x.str)}(
        x.parser,
        x.str,
        x.cursor+2,
        getlen(tape[x.cursor+1]),
        x.cursor + getlen(tape[x.cursor])-1,
    )
end

@inline function asstring(x::JSONItem)
    @assert isstring(x)
    tape = gettape(x)
    @inbounds len = getlen(tape[x.cursor])-1
    @inbounds offset = Int64(tape[x.cursor+1])
    @inbounds SubString(x.str, offset:(offset+len))
end

@inline function asint(x::JSONItem)
    @assert isint(x)
    tape = gettape(x)
    @inbounds Core.bitcast(Int64, tape[x.cursor+1])
end

@inline function asfloat(x::JSONItem)
    tape = gettape(x)
    @inbounds u = tape[x.cursor+1]
    if isint(x)
        # todo: remove this branch by not converting the float into an integer in the tape!
        Float64(Core.bitcast(Int64, u))
    else
        @assert isfloat(x)
        @inbounds Core.bitcast(Float64, tape[x.cursor+1])
    end
end

@inline function asbool(x::JSONItem)
    @assert isbool(x)
    tape = gettape(x)
    @inbounds getnontypemask(tape[x.cursor]) == UInt64(1)
end

struct PointerString <: AbstractString
    ptr::Ptr{UInt8}
    len::Int
end

if isdefined(Base, :memhash)
    function Base.hash(s::PointerString, h::UInt)
        h += Base.memhash_seed
        ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), s.ptr, s.len, h % UInt32) + h
    end
end

import Base: ==
function ==(x::String, y::PointerString)
    sizeof(x) == y.len && ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(x), y.ptr, y.len) == 0
end
==(y::PointerString, x::String) = x == y

Base.codeunit(s::PointerString) = UInt8
Base.ncodeunits(s::PointerString) = s.len
@inline function Base.codeunit(s::PointerString, i::Integer)
    @boundscheck checkbounds(s, i)
    unsafe_load(s.ptr + i - 1)
end
Base.String(x::PointerString) = unsafe_string(x.ptr, x.len)

function reverseescapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('/')  && return UInt8('/')
    b == UInt8('b')  && return UInt8('\b')
    b == UInt8('f')  && return UInt8('\f')
    b == UInt8('n')  && return UInt8('\n')
    b == UInt8('r')  && return UInt8('\r')
    b == UInt8('t')  && return UInt8('\t')
    return 0x00
end

utf16_get_supplementary(lead::UInt16, trail::UInt16) = Char(UInt32(lead-0xd7f7)<<10 + trail)

charvalue(b) = (UInt8('0') <= b <= UInt8('9')) ? b - UInt8('0') :
               (UInt8('a') <= b <= UInt8('f')) ? b - (UInt8('a') - 0x0a) :
               (UInt8('A') <= b <= UInt8('F')) ? b - (UInt8('A') - 0x0a) :
               throw(ArgumentError("JSON invalid unicode hex value"))

@noinline invalid_escape(str) = throw(ArgumentError("encountered invalid escape character in json string: \"$(String(str))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

function unescape(s)
    n = ncodeunits(s)
    buf = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = codeunit(s, i)
            if b == UInt8('\\')
                i += 1
                i > n && invalid_escape(s)
                b = codeunit(s, i)
                if b == UInt8('u')
                    c = 0x0000
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    ch = Char(c)
                    # a high surrogate followed by an escaped low surrogate is one character;
                    # any other surrogate stays a lone surrogate, as in JSON.jl
                    if 0xd800 <= c <= 0xdbff && i + 6 <= n &&
                       codeunit(s, i + 1) == UInt8('\\') && codeunit(s, i + 2) == UInt8('u')
                        c2 = 0x0000
                        c2 = (c2 << 4) + charvalue(codeunit(s, i + 3))
                        c2 = (c2 << 4) + charvalue(codeunit(s, i + 4))
                        c2 = (c2 << 4) + charvalue(codeunit(s, i + 5))
                        c2 = (c2 << 4) + charvalue(codeunit(s, i + 6))
                        if 0xdc00 <= c2 <= 0xdfff
                            ch = utf16_get_supplementary(c, c2)
                            i += 6
                        end
                    end
                    st = codeunits(Base.string(ch))
                    for j = 1:length(st)-1
                        @inbounds buf[len] = st[j]
                        len += 1
                    end
                    b = st[end]
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(s)
                end
            end
            @inbounds buf[len] = b
            len += 1
            i += 1
        end
    end
    resize!(buf, len - 1)
    return String(buf)
end

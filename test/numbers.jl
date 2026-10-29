# number parsing edge cases; these must behave the same on Parsers 2 and Parsers 3
using JSON3, StructTypes, Test

struct NumF32
    x::Float32
end
StructTypes.StructType(::Type{NumF32}) = StructTypes.Struct()

struct NumAny
    x::Any
end
StructTypes.StructType(::Type{NumAny}) = StructTypes.Struct()

@testset "floats" begin
    # integral floats read as Int64 by default, so the sign of zero only survives as a Float64
    @test JSON3.read("-0.0") === Int64(0)
    @test JSON3.read("[-0.0]"; numbertype=Float64)[1] === -0.0
    @test JSON3.read("-0.0", Float64) === -0.0
    @test JSON3.read("-0.0", Any) === Int64(0)
    @test JSON3.read("1.5") === 1.5
    @test JSON3.read("+1") === Int64(1)
    @test JSON3.read("1E5") === Int64(100000)
    @test JSON3.read("1.25e-3") === 0.00125
    @test JSON3.read("1e-400") === Int64(0)
    @test JSON3.read("1e-400", Float64) === 0.0
    # overflow to Inf is only allowed with allow_inf, or when reading into a type
    @test_throws ArgumentError JSON3.read("1e400")
    @test_throws ArgumentError JSON3.read("[1e400]")
    @test JSON3.read("1e400"; allow_inf=true) === Inf
    @test JSON3.read("-1e400"; allow_inf=true) === -Inf
    @test JSON3.read("1e400", Any) === Inf
    @test JSON3.read("1e400", Float64) === Inf
    @test JSON3.read("{\"x\":1e400}", NumF32).x === Inf32
    @test JSON3.read("{\"x\":3.4e39}", NumF32).x === Inf32
    # malformed numbers
    for s in ("1e", "1e+", "-", "+", "[1e]", "[-]", "{\"x\":1e}")
        @test_throws ArgumentError JSON3.read(s)
    end
    @test_throws ArgumentError JSON3.read("1e", Float64)
    @test_throws ArgumentError JSON3.read("1e", Any)
    @test_throws ArgumentError JSON3.read("{\"x\":1e}", NumF32)
    # hex isn't JSON: the number ends at the 0
    @test JSON3.read("0x10") === Int64(0)
    @test JSON3.read("0x10", Int) === 0
    @test JSON3.read("0x10", Any) === Int64(0)
    @test_throws ArgumentError JSON3.read("[0x10]")
    @test_throws ArgumentError JSON3.read("[0x1p3]", Vector{Float64})
    @test_throws ArgumentError JSON3.read("[0x10]", Vector{Int})
    @test_throws ArgumentError JSON3.read("{\"x\":0x10}", NumF32)
end

@testset "NaN and Inf" begin
    @test_throws ArgumentError JSON3.read("NaN")
    @test_throws ArgumentError JSON3.read("Inf")
    @test JSON3.read("NaN"; allow_inf=true) === NaN
    @test JSON3.read("Inf"; allow_inf=true) === Inf
    @test JSON3.read("-Infinity"; allow_inf=true) === -Inf
    @test isequal(JSON3.read("[NaN,Infinity,-Inf]"; allow_inf=true), [NaN, Inf, -Inf])
    @test JSON3.read("{\"x\":-Infinity}", NumF32; allow_inf=true).x === -Inf32
    @test JSON3.read("{\"x\":NaN}", NumAny; allow_inf=true).x === NaN
end

@testset "integers" begin
    @test JSON3.read("9223372036854775807") === typemax(Int64)
    @test JSON3.read("-9223372036854775808") === typemin(Int64)
    # just outside Int64 range: read as Float64
    @test JSON3.read("9223372036854775808") === 9.223372036854775808e18
    @test JSON3.read("-9223372036854775809") === -9.223372036854775809e18
    # integral values with > 53 bits of precision given in exponent form
    @test JSON3.read("1e17") === 100000000000000000
    @test JSON3.read("9.007199254740994e15") === 9007199254740994
    @test JSON3.read("9007199254740993") === 9007199254740993
    @test JSON3.read("[1,2.5]") == [1, 2.5]
    @test JSON3.read("[1,2]"; numbertype=Float64) == [1.0, 2.0]
    @test eltype(JSON3.read("[1,2]"; numbertype=Float64)) == Float64
    @test JSON3.read("12", Any) === Int64(12)
    @test JSON3.read("1.5", Any) === 1.5
    @test JSON3.read("12", Int) === 12
    @test JSON3.read("-0", Int) === 0
    @test_throws ArgumentError JSON3.read("9223372036854775808", Int)
    @test_throws ArgumentError JSON3.read("256", UInt8)
    # a leading `+` (or `-0`) is accepted for unsigned types, as for signed ones
    @test JSON3.read("[+5]", Vector{UInt8}) == UInt8[5]
    @test JSON3.read("[+5]", Vector{UInt128}) == UInt128[5]
    @test JSON3.read("[-0]", Vector{UInt64}) == UInt64[0]
    @test JSON3.read("\"+5\"", UInt64; parsequoted=true) === UInt64(5)
    @test_throws ArgumentError JSON3.read("[+]", Vector{UInt8})
    @test_throws ArgumentError JSON3.read("[++5]", Vector{UInt8})
    @test_throws ArgumentError JSON3.read("[+-5]", Vector{UInt8})
end

@testset "number types" begin
    @test JSON3.read("1.5", Float32) === 1.5f0
    @test JSON3.read("1.5", Float16) === Float16(1.5)
    @test JSON3.read("[1.5,2]", Vector{Float32}) == Float32[1.5, 2]
    @test JSON3.read("0.1", BigFloat) == BigFloat("0.1")
    @test JSON3.read("1e400", BigFloat) == BigFloat("1e400")
    @test JSON3.read("170141183460469231731687303715884105727", Int128) === typemax(Int128)
    @test JSON3.read("340282366920938463463374607431768211455", UInt128) === typemax(UInt128)
    @test JSON3.read("123456789012345678901234567890", BigInt) == big"123456789012345678901234567890"
    @test JSON3.read("[-5]", Vector{Int8}) == Int8[-5]
    # types without a dedicated parser
    @test JSON3.read("12", Rational{Int}) === 12//1
    @test JSON3.read("1.5", Rational{Int}) === 3//2
    @test JSON3.read("[1.5]", Vector{Real}) == Real[1.5]
    @test JSON3.read("12", AbstractFloat) === 12.0
    @test JSON3.read("12", Integer) == 12
end

@testset "end of buffer" begin
    @test JSON3.read("7") === Int64(7)
    @test JSON3.read("7.5") === 7.5
    @test JSON3.read(" 7 ") === Int64(7)
    @test JSON3.read("[7]") == [7]
    @test JSON3.read("{\"a\":7}")[:a] === Int64(7)
    @test JSON3.read(UInt8['4', '2']) === Int64(42)
    @test JSON3.read(view(UInt8['[', '4', '2', ']', 'x'], 1:4)) == [42]
    @test JSON3.read("7", Float32) === 7.0f0
    @test JSON3.read(SubString("[1,2]x", 1, 5)) == [1, 2]
end

@testset "quoted numbers" begin
    @test JSON3.read("\"12\"", Int; parsequoted=true) === 12
    @test JSON3.read("\"1.5\"", Float64; parsequoted=true) === 1.5
    @test JSON3.read("{\"x\":\"2.5\"}", NumF32; parsequoted=true).x === 2.5f0
    @test JSON3.read("[\"1\",2]", Vector{Int}; parsequoted=true) == [1, 2]
    @test_throws ArgumentError JSON3.read("\"12\"", Int)
end

tryparse_json(s, T) = try JSON3.read(s, T) catch e; e isa ArgumentError ? nothing : rethrow() end

@testset "review regressions" begin
    # 2^63 doesn't fit in an Int64, so an integral float that rounds to it stays a float
    @test JSON3.read("9223372036854775807.0") === 9.223372036854775807e18
    @test JSON3.read("[9223372036854775807.0]") == [9.223372036854775807e18]
    @test JSON3.read("9223372036854775807.0", Any) === 9.223372036854775807e18
    # typed Any reads keep > 53-bit integers exact, like untyped reads
    @test JSON3.read("9007199254740993", Any) === 9007199254740993
    @test JSON3.read("9223372036854775807", Any) === typemax(Int64)
    @test JSON3.read("{\"x\":9007199254740993}", NumAny).x === 9007199254740993
    @test JSON3.read("1e17", Any) === 100000000000000000
    # malformed quoted numbers are invalid input
    for (s, T) in (("\"1e\"", Float64), ("\"-\"", Int), ("\"1e5\"", Int), ("\"x\"", Int))
        @test_throws ArgumentError JSON3.read(s, T; parsequoted=true)
    end
    # Parsers 2 read `f` as an exponent marker; never stop silently at the `f`
    # (Parsers 2 gives 1e5, Parsers 3 rejects)
    for s in ("1F5", "1f5")
        @test something(tryparse_json(s, Float64), 1e5) === 1e5
    end
    @test JSON3.read("1e100000", BigFloat) == BigFloat("1e100000")
    @test JSON3.read("1e-100000", BigFloat) == BigFloat("1e-100000")
end

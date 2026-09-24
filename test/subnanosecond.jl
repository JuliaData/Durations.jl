module SubnanosecondTests
using Test, Dates, Durations
using Dates: value
include("../examples/subnanosecond.jl")
using .Subnanosecond: Picosecond, Femtosecond, Attosecond

@testset "Int128 sub-nanosecond prototype" begin
    for (P, scale, digits) in ((Picosecond, 1_000, 12),
                              (Femtosecond, 1_000_000, 15),
                              (Attosecond, 1_000_000_000, 18))
        T = Timestamp{P}
        origin = T(2026, 9, 24)
        x = origin + P(1)
        @test isprimitivetype(P)
        @test isbitstype(T) && sizeof(T) == 16
        @test value(origin) == Int128(value(Timestamp(2026, 9, 24))) * scale
        @test x - origin == P(1)
        @test string(P(1)) == "1 " * lowercase(string(nameof(P)))
        @test origin < x < origin + Nanosecond(1)
        @test P(1) + origin == x
        @test x - P(1) == origin
        @test_throws ArgumentError T(Year(2026), P(1))
        @test_throws ArgumentError T(P(1))
        @test x + Month(1) == T(2026, 10, 24) + P(1)
        @test floor(x, Nanosecond) == origin
        @test ceil(x, Nanosecond) == origin + Nanosecond(1)
        @test round(origin + P(scale ÷ 2), Nanosecond) == origin + Nanosecond(1)
        @test floor(origin + P(17), P(10)) == origin + P(10)
        @test Timestamp{Nanosecond}(origin) == Timestamp(2026, 9, 24)
        @test_throws InexactError Timestamp{Nanosecond}(x)
        @test_throws InexactError Time(x)
        @test DateTime(x) == DateTime(2026, 9, 24)
        @test Date(x) == Date(2026, 9, 24)
        @test Date(T(3000)) == Date(3000)
        @test string(x) == "2026-09-24T00:00:00." * "0"^(digits-1) * "1"
        @test eval(Meta.parse(repr(x))) == x
        @test hash(origin) == hash(Timestamp(2026, 9, 24))
        @test hash(Timestamp{Attosecond}(x)) == hash(x)
        @test convert(P, x) == P(value(x))
        @test value(Durations.unix2timestamp(T, 1)) == Int128(10)^digits
        @test Durations.timestamp2unix(origin) isa Float64
        @test Durations.unix2timestamp(T, 1//2) == convert(T, P(Int128(10)^digits ÷ 2))
        @test collect(origin:P(1):origin+P(3)) == [origin + P(i) for i in 0:3]
        @test typemax(T) + P(1) === typemin(T)
        @test typemin(T) - P(1) === typemax(T)
        @test typemax(T) - typemin(T) === P(-1)
        @test_throws InexactError ceil(typemax(T), Nanosecond)
        @test_throws InexactError floor(typemin(T), Nanosecond)
        for n in (typemin(Int128), Int128(-1), Int128(0), Int128(1), typemax(Int128))
            raw = convert(T, P(n))
            @test value(raw) === n
            @test only(reinterpret(Int128, [raw])) === n
            @test convert(T, convert(P, raw)) === raw
        end
        before = convert(T, P(-1))
        @test Date(before) == Date(1969, 12, 31)
        @test Dates.nanosecond(before) == 999
        @test floor(before, Nanosecond) == convert(T, Nanosecond(-1))
    end
    pico = Timestamp{Picosecond}(2026) + Picosecond(1)
    femto = Timestamp{Femtosecond}(pico) + Femtosecond(1)
    @test femto - pico == Femtosecond(1)
    @test promote(pico, femto) == (Timestamp{Femtosecond}(pico), femto)
    @test pico < femto
    @test_throws InexactError Timestamp{Picosecond}(femto)
    wide = Timestamp{Picosecond}(10^18)
    @test year(wide) == 10^18
    @test_throws InexactError Date(wide)
    @test_throws ArgumentError Timestamp{Picosecond}(Int64(year(typemax(Timestamp{Picosecond}))), 12, 31)
    @test isempty(Test.detect_ambiguities(Subnanosecond; recursive=true))
end
end

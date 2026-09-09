using Test, Dates, Random, Durations
using Dates: CompoundPeriod

@testset "Duration" begin
    @test isbitstype(Duration)
    @test sizeof(Duration) == 16
    @test fieldtypes(Duration) == (Int32, Int32, Int64)
    @test ntuple(i -> fieldoffset(Duration, i), 3) == (0, 4, 8)
    @test Duration() == zero(Duration)
    @test Duration(months=1, days=-2, nanoseconds=3) == Duration(1,-2,3)
    @test Duration(Duration(1,2,3)) === Duration(1,2,3)
    @test iszero(Duration())
    @test !iszero(Duration(0,0,1))
    @test Duration(0,1,0) != Duration(0,0,86_400_000_000_000)
    @test Duration(1,0,0) != Duration(0,30,0)
    @test Duration(0,1,-86_400_000_000_000) != zero(Duration)
    @test_throws MethodError isless(Duration(1,0,0), Duration(0,30,0))
    @test_throws MethodError Duration(1.5,0,0)
    for i in (Int128(typemin(Int32))-1, Int128(typemax(Int32))+1)
        @test_throws InexactError Duration(i,0,0)
        @test_throws InexactError Duration(0,i,0)
    end
    for n in (Int128(typemin(Int64))-1, Int128(typemax(Int64))+1)
        @test_throws InexactError Duration(0,0,n)
    end
    @test Duration(1,2,3) + Duration(-2,3,-4) == Duration(-1,5,-1)
    @test Duration(1,2,3) - Duration(-2,3,-4) == Duration(3,-1,7)
    @test -Duration(1,-2,3) == Duration(-1,2,-3)
    @test +Duration(1,2,3) == Duration(1,2,3)
    @test 2 * Duration(1,2,3) == Duration(1,2,3) * 2 == Duration(2,4,6)
    @test zero(Duration) * big(10)^100 == zero(Duration)
    @test sum([Duration(1,2,3),Duration(2,3,4)]) == Duration(3,5,7)
    @test Duration(1,2,3) .+ [Duration(2,3,4)] == [Duration(3,5,7)]
    @test eval(Meta.parse(repr(Duration(1,-2,3)))) == Duration(1,-2,3)
    for x in (Duration(typemax(Int32),0,0), Duration(0,typemax(Int32),0), Duration(0,0,typemax(Int64)))
        @test_throws OverflowError x + x
        @test_throws OverflowError x * 2
    end
    for x in (Duration(typemin(Int32),0,0), Duration(0,typemin(Int32),0), Duration(0,0,typemin(Int64)))
        @test_throws OverflowError -x
        @test_throws OverflowError x - Duration(1,1,1)
    end
    for (p, expected) in ((Year(2),Duration(24,0,0)),(Quarter(2),Duration(6,0,0)),
                           (Month(-2),Duration(-2,0,0)),(Week(-2),Duration(0,-14,0)),
                           (Day(2),Duration(0,2,0)),(Hour(1),Duration(0,0,3_600_000_000_000)),
                           (Minute(1),Duration(0,0,60_000_000_000)),(Second(1),Duration(0,0,1_000_000_000)),
                           (Millisecond(1),Duration(0,0,1_000_000)),(Microsecond(1),Duration(0,0,1000)),
                           (Nanosecond(-1),Duration(0,0,-1)))
        @test Duration(p) == expected
        @test convert(Duration,p) == expected
    end
    @test Duration(Month(2)+Day(-3)+Nanosecond(5)) == Duration(2,-3,5)
    @test_throws InexactError Duration(Year(typemax(Int64)))
    @test_throws InexactError Duration(Hour(typemax(Int64)))
    rng = MersenneTwister(12)
    for _ in 1:1000
        x = Duration(rand(rng,Int32),rand(rng,Int32),rand(rng,Int64))
        @test Duration(CompoundPeriod(x)) == x
        @test convert(Duration,convert(CompoundPeriod,x)) == x
        @test hash(x) == hash(Duration(x.months,x.days,x.nanoseconds))
        @test length(Set([x,x])) == 1
        # Verify bytes against an independent field-by-field host-endian encoder.
        io = IOBuffer(); write(io,x.months); write(io,x.days); write(io,x.nanoseconds)
        @test collect(reinterpret(UInt8,[x])) == take!(io)
        @test reinterpret(Duration,collect(reinterpret(UInt8,[x])))[1] == x
    end
    @test isempty(Test.detect_ambiguities(Durations, Dates; recursive=true))
end

include("timestamps.jl")

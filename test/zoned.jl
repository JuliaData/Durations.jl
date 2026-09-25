# ZonedTimestamp without TimeZones.jl. Run before the tests that load TimeZones,
# including Arrow 2.x, which depends on it.
using Durations: ZonedTimestamp

# the `y` format code accepts a leading sign starting with the Julia 1.12 Dates stdlib
const PARSES_NEGATIVE_YEARS = tryparse(DateTime, "-0001-01-01", dateformat"yyyy-mm-dd") !== nothing

@testset "ZonedTimestamp" begin
    @test Base.get_extension(Durations, :DurationsTimeZonesExt) === nothing

    @testset "Layout and zero-copy" begin
        for P in (Second, Millisecond, Microsecond, Nanosecond),
            Z in (:UTC, Symbol("+07:30"), Symbol("-05:00"), Symbol("America/Denver"), Symbol("Vendor/Unknown"))
            T = ZonedTimestamp{P,Z}
            @test isbitstype(T) && sizeof(T) == 8
            counts = Int64[typemin(Int64), -1, 0, 1, typemax(Int64)]
            v = reinterpret(T, counts)  # an Arrow buffer, read in place
            @test pointer(parent(v)) == pointer(counts)
            @test Dates.value.(v) == counts
            @test [x.utc for x in v] == reinterpret(Timestamp{P}, counts)
            @test reinterpret(Int64, collect(v)) == counts
            # instant operations need no zone rules
            @test sort(v[[3, 1, 5, 2, 4]]) == v
            @test v[2] < v[3] && v[3] - v[2] == P(1) && v[3] + P(1) == v[4]
            @test hash(v[3]) == hash(T(Timestamp{P}(1970), UTC))
            @test all(x -> !PARSES_NEGATIVE_YEARS && startswith(string(x), '-') || T(string(x)) == x, v)
            @test all(x -> eval(Meta.parse(repr(x))) === x, v)
            @test Durations.zonename(T) == Durations.zonename(v[1]) == String(Z)
        end
        @test_throws ArgumentError ZonedTimestamp{Nanosecond,Symbol("")}(Timestamp(2026), UTC)
        @test_throws ArgumentError ZonedTimestamp{Nanosecond,1}(Timestamp(2026), UTC)
    end

    @testset "UTC and fixed offsets" begin
        J = ZonedTimestamp{Nanosecond,Symbol("+07:00")}
        zt = J(Timestamp(2026, 3, 8, 16, 0, 0, 0, 0, 5))  # local time
        @test zt.utc == Timestamp(2026, 3, 8, 9, 0, 0, 0, 0, 5)
        @test J(zt.utc, UTC) == zt
        @test J(2026, 3, 8, 16, 0, 0, 0, 0, 5) == zt == J(Date(2026, 3, 8), Time(16, 0, 0, 0, 0, 5))
        @test Timestamp(zt) == Timestamp{Nanosecond}(zt) == Timestamp(2026, 3, 8, 16, 0, 0, 0, 0, 5)
        @test Timestamp(zt, UTC) == Timestamp{Nanosecond}(zt, UTC) == zt.utc
        @test (year(zt), month(zt), day(zt), hour(zt), minute(zt), nanosecond(zt)) == (2026, 3, 8, 16, 0, 5)
        @test Date(zt) == Date(2026, 3, 8) && Time(zt) == Time(16, 0, 0, 0, 0, 5)
        @test DateTime(zt) == DateTime(2026, 3, 8, 16)
        @test ZonedTimestamp{Millisecond,Symbol("-05:30")}(2026, 1, 1).utc == Timestamp{Millisecond}(2026, 1, 1, 5, 30)
        # the same time in another zone
        u = Durations.astimezone(zt, :UTC)
        @test u isa ZonedTimestamp{Nanosecond,:UTC} && Durations.astimezone(zt, "UTC") === u
        @test u == zt && hash(u) == hash(zt) && Dict(zt => 1)[u] == 1 && hour(u) == 9
        @test ZonedTimestamp{Microsecond,:UTC}(zt - Nanosecond(5)) == zt - Nanosecond(5)
        @test_throws InexactError ZonedTimestamp{Microsecond,:UTC}(zt)
        # time periods move the instant; date periods move the local calendar
        @test zt + Hour(24) == zt + Day(1) && (zt + Nanosecond(7)) - zt == Nanosecond(7)
        m = J(2026, 1, 31, 3)  # 2026-01-30T20:00 UTC
        @test Timestamp(m + Month(1)) == Timestamp(2026, 2, 28, 3)
        @test Timestamp(m - Month(1)) == Timestamp(2025, 12, 31, 3)
        @test_throws InexactError ZonedTimestamp{Second,:UTC}(Timestamp{Second}(2026), UTC) + Millisecond(1)
        # rounding uses the local time
        @test Timestamp(floor(zt, Day)) == Timestamp(2026, 3, 8)
        @test Timestamp(ceil(zt, Day)) == Timestamp(2026, 3, 9)
        @test Timestamp(round(zt, Hour)) == Timestamp(2026, 3, 8, 16)
        @test Timestamp(floor(zt, Hour)) == Timestamp(2026, 3, 8, 16)
        h = ZonedTimestamp{Millisecond,Symbol("-05:30")}(2026, 1, 1, 10, 45)
        @test Timestamp(floor(h, Hour)) == Timestamp{Millisecond}(2026, 1, 1, 10)
        # Dates functions that build on the above
        @test Timestamp(firstdayofmonth(zt)) == Timestamp(2026, 3, 1)
        @test dayofweek(zt) == Sunday && Timestamp(tonext(zt, Monday)) == Timestamp(2026, 3, 9, 16, 0, 0, 0, 0, 5)
        @test collect(zt:Hour(6):zt + Day(1)) == [zt + Hour(6i) for i in 0:4]
        @test Dates.format(zt, "yyyy-mm-dd HH:MM") == "2026-03-08 16:00"
        @test eltype([zt, ZonedTimestamp{Millisecond,Symbol("+07:00")}(Timestamp{Millisecond}(2026), UTC)]) == J
        @test Timestamp(now(ZonedTimestamp{Microsecond,:UTC}), UTC) isa Timestamp{Microsecond}
    end

    @testset "Named zones without TimeZones.jl" begin
        D = ZonedTimestamp{Nanosecond,Symbol("America/Denver")}
        d = D(Timestamp(2026, 3, 8, 9), UTC)
        @test d == Durations.astimezone(d, :UTC) && d < d + Hour(1) && (d + Hour(1)) - d == Hour(1)
        @test string(d) == "2026-03-08T09:00:00Z[America/Denver]"  # UTC; the offset is unknown
        err = try hour(d) catch e; e end
        @test err isa ArgumentError && occursin("TimeZones.jl", err.msg)
        @test_throws ArgumentError D(Timestamp(2026, 3, 8))
        @test_throws ArgumentError d + Day(1)
    end

    @testset "Text" begin
        for zt in (ZonedTimestamp{Nanosecond,Symbol("+07:30")}(Timestamp(2026, 3, 8, 16, 0, 0, 0, 0, 5)),
                   ZonedTimestamp{Second,Symbol("-05:00")}(Timestamp{Second}(1900, 1, 1)),
                   ZonedTimestamp{Millisecond,:UTC}(Timestamp{Millisecond}(2026, 12, 31, 23, 59, 59, 999), UTC),
                   ZonedTimestamp{Nanosecond,Symbol("America/Denver")}(Timestamp(2026), UTC))
            T = typeof(zt)
            @test T(string(zt)) == zt && parse(T, string(zt)) == zt
            @test eval(Meta.parse(repr(zt))) == zt
        end
        @test string(ZonedTimestamp{Nanosecond,Symbol("+07:30")}(Timestamp(2026, 3, 8, 16))) ==
              "2026-03-08T16:00:00+07:30[+07:30]"
        @test string(ZonedTimestamp{Second,:UTC}(Timestamp{Second}(2026), UTC)) == "2026-01-01T00:00:00+00:00[UTC]"
        @test_throws ArgumentError ZonedTimestamp{Nanosecond,:UTC}("2026-03-08T16:00:00+07:30[+07:30]")
        @test_throws ArgumentError ZonedTimestamp{Nanosecond,:UTC}("2026-03-08T16:00:00[UTC]")
        # the local time of the largest value is out of range, so it prints as UTC
        mx = ZonedTimestamp{Nanosecond,Symbol("+07:00")}(typemax(Timestamp), UTC)
        @test string(mx) == "2262-04-11T23:47:16.854775807Z[+07:00]"
        @test_throws OverflowError hour(mx)
        @test_throws OverflowError ZonedTimestamp{Nanosecond,Symbol("-07:00")}(typemax(Timestamp))
    end

    @testset "Invalid input and rounding limits" begin
        U = ZonedTimestamp{Nanosecond,:UTC}
        for offset in ("+24:00", "-00:60", "+99:99", "+00:00:60", "+0:00", "+０1:00")
            @test_throws ArgumentError U("2026-01-01T00:00:00" * offset * "[UTC]")
        end
        @test U("2026-01-01T00:00:30+00:00:30[UTC]") == U(2026)
        @test_throws OverflowError U(string(typemax(Timestamp)) * "-01:00[UTC]")
        @test_throws OverflowError U(string(typemin(Timestamp)) * "+01:00[UTC]")
        @test_throws ArgumentError U(Timestamp(2026); occurrence=-1)
        @test_throws ArgumentError U(Timestamp(2026); occurrence=3)
        for naive in (Date(2026), DateTime(2026), Timestamp(2026))
            @test U(2026) != naive && naive != U(2026)
            @test !isequal(U(2026), naive)
            @test length(Set([U(2026), naive])) == 2
        end
        for P in (Second, Millisecond, Microsecond, Nanosecond), bound in (typemin, typemax)
            T = ZonedTimestamp{P,:UTC}
            ts = bound(Timestamp{P})
            zt = T(ts, UTC)
            @test T(ts) == zt
            for op in (floor, ceil, round), period in (Second(7), Hour(13), Nanosecond(1))
                expected = try op(ts, period) catch e; e end
                if expected isa Exception
                    @test_throws typeof(expected) op(zt, period)
                else
                    @test op(zt, period).utc == expected
                end
            end
        end
        # Only the final UTC count must fit, even if the rounded local count does not.
        W = ZonedTimestamp{Nanosecond,Symbol("-01:00")}
        zt = W(typemin(Timestamp) + Hour(1), UTC)
        @test Dates.value(floor(zt, Second)) == -9223368437000000000
        @test_throws InexactError ceil(U(typemax(Timestamp), UTC), Second)
        @test_throws InexactError Dates.floorceil(U(typemax(Timestamp), UTC), Second(1))
    end
end

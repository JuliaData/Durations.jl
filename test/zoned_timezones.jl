# ZonedTimestamp with TimeZones.jl loaded
using TimeZones
using Durations: ZonedTimestamp

# A transition at the same UTC time as its neighbor. TimeZones.jl reports local times next to
# one as nonexistent even when they exist (the "Zero-length transitions" test set).
function zerolength(tz::VariableTimeZone, i::Int)
    t = tz.transitions
    return t[i].utc_datetime == t[i - 1].utc_datetime ||
           (i < length(t) && t[i].utc_datetime == t[i + 1].utc_datetime)
end

seconds(dt::DateTime) = fld(Dates.value(dt) - Dates.UNIXEPOCH, 1000)

# The UTC times for local time `local_dt` in `tz`: none in a gap, two in a fold
function utctimes(local_dt::DateTime, tz::TimeZone)
    try
        return [DateTime(ZonedDateTime(local_dt, tz), UTC)]
    catch e
        e isa TimeZones.NonExistentTimeError && return DateTime[]
        e isa TimeZones.AmbiguousTimeError || rethrow()
        return [DateTime(ZonedDateTime(local_dt, tz, k), UTC) for k in (1, 2)]
    end
end

# Probes near every transition from 1900 until the rules end: UTC times on each side of the
# transition, and local times at, near, and inside each gap or fold
function probes(tz::VariableTimeZone)
    last = something(tz.cutoff, DateTime(2100)) - Day(2)
    utcs, locals = DateTime[], DateTime[]
    for (i, t) in enumerate(tz.transitions)
        (i == 1 || t.utc_datetime < DateTime(1900) || t.utc_datetime > last || zerolength(tz, i)) && continue
        push!(utcs, t.utc_datetime - Millisecond(1), t.utc_datetime)
        for edge in (t.utc_datetime + t.zone.offset, t.utc_datetime + tz.transitions[i - 1].zone.offset),
            d in (-1, 0, 1, -1800_000, 1800_000)
            push!(locals, edge + Millisecond(d))
        end
    end
    return utcs, locals
end

# Disagreements with TimeZones.jl of the zone rules Durations builds for `name`
function ruledisagreements(name::String)
    tz = TimeZone(name, TimeZones.Class(:ALL))
    r = Durations.zonerules(Symbol(name))
    tz isa VariableTimeZone || return Int(r.offsets != [Dates.value(tz.offset)])
    utcs, locals = probes(tz)
    bad = count(utc -> utc + Second(Durations.ruleoffset(r, seconds(utc))) !=
                       DateTime(ZonedDateTime(utc, tz; from_utc=true)), utcs)
    bad += count(locals) do local_dt
        ours = [local_dt - Second(r.offsets[i]) for i in Durations.localrules(r, seconds(local_dt))]
        return ours != utctimes(local_dt, tz)
    end
    return bad
end

# Disagreements with TimeZones.jl of the public API, through a `ZonedTimestamp` type
function apidisagreements(name::String)
    tz = TimeZone(name, TimeZones.Class(:ALL))
    T = ZonedTimestamp{Millisecond,Symbol(name)}
    utcs, locals = probes(tz)
    bad = count(utc -> DateTime(T(Timestamp{Millisecond}(utc), UTC)) != DateTime(ZonedDateTime(utc, tz; from_utc=true)), utcs)
    bad += count(locals) do local_dt
        theirs = utctimes(local_dt, tz)
        ours = try
            [DateTime(Timestamp(T(Timestamp{Millisecond}(local_dt)), UTC))]
        catch e
            e isa Durations.NonExistentTimeError ? DateTime[] :
                [DateTime(Timestamp(T(Timestamp{Millisecond}(local_dt); occurrence=k), UTC)) for k in (1, 2)]
        end
        return ours != theirs
    end
    return bad
end

@testset "ZonedTimestamp with TimeZones.jl" begin
    @test Base.get_extension(Durations, :DurationsTimeZonesExt) !== nothing
    D = ZonedTimestamp{Nanosecond,Symbol("America/Denver")}

    @testset "Every zone agrees with TimeZones.jl" begin
        @test sum(ruledisagreements, TimeZones.timezone_names()) == 0
        # 30-minute and negative daylight saving time, and offsets of 45 minutes
        @test sum(apidisagreements, ("America/Denver", "Australia/Lord_Howe", "Europe/Dublin", "Asia/Kathmandu",
                                     "Pacific/Chatham", "Antarctica/Troll", "Africa/Casablanca")) == 0
    end

    @testset "Zero-length transitions" begin
        # Python's zoneinfo gives the same UTC times. Each of these local times occurs once.
        for (name, local_dt, utc) in (("America/Resolute", DateTime(2001, 4, 1, 2, 30), DateTime(2001, 4, 1, 7, 30)),
                                      ("America/Resolute", DateTime(2007, 3, 11, 2, 30), DateTime(2007, 3, 11, 7, 30)),
                                      ("America/Nuuk", DateTime(2023, 10, 28, 23, 30), DateTime(2023, 10, 29, 1, 30)))
            zt = ZonedTimestamp{Millisecond,Symbol(name)}(Timestamp{Millisecond}(local_dt))
            @test Timestamp(zt, UTC) == utc && Timestamp(zt) == local_dt
        end
        zones = [n for n in TimeZones.timezone_names() if (tz = TimeZone(n, TimeZones.Class(:ALL))) isa VariableTimeZone &&
                 any(i -> zerolength(tz, i), 2:length(tz.transitions))]
        @test length(zones) < 10  # the comparison above skips few transitions
    end

    @testset "DST fold and gap" begin
        fold = Timestamp(2026, 11, 1, 1, 30, 0, 0, 0, 1)
        @test_throws Durations.AmbiguousTimeError D(fold)
        a, b = D(fold; occurrence=1), D(fold; occurrence=2)
        @test b - a == Hour(1) && Timestamp(a) == Timestamp(b) == fold
        @test string(a) == "2026-11-01T01:30:00.000000001-06:00[America/Denver]"
        @test string(b) == "2026-11-01T01:30:00.000000001-07:00[America/Denver]"
        @test D(string(b)) == b
        @test_throws Durations.NonExistentTimeError D(Timestamp(2026, 3, 8, 2, 30))
        t = Timestamp(2026, 3, 8, 9)  # at this UTC time, 02:00 MST becomes 03:00 MDT
        @test Timestamp(D(t - Nanosecond(1), UTC)) == Timestamp(2026, 3, 8, 1, 59, 59, 999, 999, 999)
        @test Timestamp(D(t, UTC)) == Timestamp(2026, 3, 8, 3)
        @test D(Timestamp(2026, 3, 8, 1, 59, 59, 999, 999, 999)) == D(t - Nanosecond(1), UTC)
    end

    @testset "Calendar and elapsed arithmetic" begin
        noon = D(2026, 3, 7, 12, 0, 0, 0, 0, 5)
        @test Timestamp(noon + Day(1)) == Timestamp(2026, 3, 8, 12, 0, 0, 0, 0, 5)
        @test (noon + Day(1)) - noon == Hour(23)
        @test Timestamp(noon + Hour(24)) == Timestamp(2026, 3, 8, 13, 0, 0, 0, 0, 5)
        @test_throws Durations.NonExistentTimeError D(2026, 3, 7, 2, 30) + Day(1)
        @test Timestamp(floor(noon + Day(1), Day)) == Timestamp(2026, 3, 8)
        b = D(Timestamp(2026, 11, 1, 1, 45); occurrence=2)
        @test floor(b, Hour) == D(Timestamp(2026, 11, 1, 1); occurrence=2)
        @test [Timestamp(x) for x in noon:Day(1):noon + Day(2)] == [Timestamp(noon) + Day(i) for i in 0:2]
        @test length(noon:Hour(1):noon + Day(1)) == 24  # the day is 23 hours long
    end

    @testset "Zone names" begin
        for name in ("Etc/UTC", "GMT", "Z", "US/Mountain", "EST5EDT", "+0730", "UTC+07:30", "Europe/Paris")
            zt = ZonedTimestamp{Nanosecond,Symbol(name)}(Timestamp(2026, 7, 1), UTC)
            zdt = ZonedDateTime(DateTime(2026, 7, 1), TimeZone(name, TimeZones.Class(:ALL)); from_utc=true)
            @test DateTime(zt) == DateTime(zdt)
        end
        unknown = ZonedTimestamp{Nanosecond,Symbol("Vendor/Unknown")}(Timestamp(2026), UTC)
        @test_throws ArgumentError hour(unknown)
        @test string(unknown) == "2026-01-01T00:00:00Z[Vendor/Unknown]"
        late = D(Timestamp(2040, 1, 1), UTC)  # the rules for zones with daylight saving time end in 2038
        @test_throws ArgumentError hour(late)
        @test string(late) == "2040-01-01T00:00:00Z[America/Denver]"
    end

    @testset "ZonedDateTime" begin
        zdt = ZonedDateTime(2026, 11, 1, 1, 30, tz"America/Denver", 2)
        zt = ZonedTimestamp(zdt)
        @test zt isa ZonedTimestamp{Millisecond,Symbol("America/Denver")}
        @test zt == zdt && zdt == zt && hash(zt) == hash(zdt)
        @test isless(zt, zdt + Millisecond(1)) && isless(zdt - Millisecond(1), zt)
        @test ZonedDateTime(zt) == zdt && TimeZones.timezone(ZonedDateTime(zt)) == tz"America/Denver"
        @test ZonedDateTime(D(zt) + Nanosecond(999_999)) == zdt  # floored to the millisecond
        @test ZonedTimestamp{Nanosecond,:UTC}(zdt) == zdt
        f = ZonedTimestamp(ZonedDateTime(2026, 1, 1, FixedTimeZone("UTC+07:30")))
        @test Durations.zonename(f) == "+07:30" && hour(f) == 0
        @test TimeZones.timezone(f) == FixedTimeZone("UTC+07:30")
        paris = astimezone(zt, "Europe/Paris")
        @test paris isa ZonedTimestamp{Millisecond,Symbol("Europe/Paris")} && paris == zt && hour(paris) == 9
        @test astimezone(zt, tz"UTC") isa ZonedTimestamp{Millisecond,:UTC}
        @test Durations.astimezone(zt, tz"Europe/Paris") === paris
    end
end

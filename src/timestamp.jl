# Compatibility implementation of `Dates.Timestamp{P}` (JuliaLang/julia#62994) for
# Julia versions whose Dates stdlib does not define it. `Durations.jl` includes
# this file only when `Dates.Timestamp` is undefined; otherwise it re-exports the
# stdlib type. Keep the semantics identical to the stdlib implementation.

using Dates: Dates, AbstractDateTime, TimeType, Date, DateTime, Time, UTC,
    Period, DatePeriod, TimePeriod, FixedPeriod,
    Year, Quarter, Month, Week, Day, Hour, Minute, Second, Millisecond, Microsecond, Nanosecond,
    UTInstant, DateFormat, value, days,
    year, month, day, hour, minute, second, millisecond, microsecond, nanosecond,
    yearmonth, yearmonthday, week, quarter, dayofweek

"""
    Timestamp{P}

`Timestamp` represents a point in time according to the proleptic Gregorian
calendar with resolution `P`, one of `Second`, `Millisecond`, `Microsecond`,
or `Nanosecond`. Its value is an `Int64` count of units of `P` since the Unix
epoch, `1970-01-01T00:00:00`. `Timestamp(args...)` defaults to `Timestamp{Nanosecond}`;
`Timestamp(ts::Timestamp)` preserves the input's resolution. Use a concrete
`Timestamp{P}` for array elements and struct fields of a known resolution.

Nanosecond resolution in 64 bits bounds the representable range to
`1677-09-21T00:12:43.145224192` through `2262-04-11T23:47:16.854775807`
(`typemin(Timestamp)` and `typemax(Timestamp)`); constructing a `Timestamp`
outside this range throws an `ArgumentError`. Like `DateTime`, the type uses
fixed-point arithmetic and is thus prone to underflowing and overflowing:
adding a period that would leave the representable range wraps around rather
than throwing. In particular, `typemax(Timestamp{P}) + P(1)` is
`typemin(Timestamp{P})`.

Coarser resolutions cover approximately ±292 billion years (`Second`),
±292 million years (`Millisecond`), or ±292 thousand years (`Microsecond`).
`DateTime` keeps its existing representation and API. Unlike `DateTime`,
`Timestamp{Millisecond}` counts from the Unix epoch.

Constructors, parsing, and conversions between resolutions require exact
representation. Use `floor`, `ceil`, or `round` before converting to a coarser
resolution to discard precision explicitly. Period arithmetic preserves `P`
and requires a duration representable in units of `P`. Unlike `DateTime`, it
throws an `InexactError` instead of rounding a finer duration. Rounding throws an
`InexactError` if the requested result is not representable; it does not wrap.

The types compare directly, even outside their shared range. Mixed arithmetic
promotes to the finer resolution, so both values must fit that resolution.
For promotion with `DateTime`, its resolution is `Millisecond`.

`Dates.value(ts)` is the raw count since the Unix epoch. `convert(P, ts)`
returns that count as a period in units of `P`, requiring exact conversion;
`P(ts)` instead returns the corresponding calendar component.

This definition is provided by Durations.jl on Julia versions whose `Dates`
stdlib lacks `Timestamp`. On later versions `Durations.Timestamp` is
`Dates.Timestamp` itself.
"""
struct Timestamp{P<:Union{Second,Millisecond,Microsecond,Nanosecond}} <: AbstractDateTime
    instant::UTInstant{P}
    Timestamp{P}(instant::UTInstant{P}) where {P} = new{P}(instant)
end

Timestamp(args...; kwargs...) = Timestamp{Nanosecond}(args...; kwargs...)
Timestamp(instant::UTInstant{P}) where {P} = Timestamp{P}(instant)
Timestamp(ts::Timestamp) = ts

const NS_PER_DAY = Int64(86400000000000)
const UNIXEPOCHDAYS = Dates.totaldays(1970, 1, 1)

timestamp_scale(::Type{Second}) = Int64(1000000000)
timestamp_scale(::Type{Millisecond}) = Int64(1000000)
timestamp_scale(::Type{Microsecond}) = Int64(1000)
timestamp_scale(::Type{Nanosecond}) = Int64(1)
timestamp_scale(::Type{Timestamp{P}}) where {P} = timestamp_scale(P)
timestamp_ticks_per_day(::Type{P}) where {P} = NS_PER_DAY ÷ timestamp_scale(P)
timestamp_finer(::Type{P}, ::Type{Q}) where {P,Q} =
    timestamp_scale(P) <= timestamp_scale(Q) ? P : Q

function timestamp_ticks(::Type{P}, ns::Integer) where {P}
    ticks, remainder = divrem(ns, timestamp_scale(P))
    iszero(remainder) || throw(InexactError(:convert, Timestamp{P}, ns))
    return ticks
end

timestamp_from_day(::Type{Timestamp{P}}, rata, ns) where {P} =
    Timestamp{P}(UTInstant(P(timestamp_ticks(P, (Int128(rata) - UNIXEPOCHDAYS) * NS_PER_DAY + ns))))

### Constructors

"""
    Timestamp{P}(y, [m, d, h, mi, s, ms, us, ns])::Timestamp{P}

Construct a `Timestamp` type by parts. Arguments must be convertible to
`Int64` and the result must lie within the representable range
(`typemin(Timestamp{P})` to `typemax(Timestamp{P})`) at resolution `P`.
The `ns` argument can contain a full fractional second, but the
combined `ms`, `us`, and `ns` arguments must be less than one second.
"""
function Timestamp{P}(y::Int64, m::Int64=1, d::Int64=1, h::Int64=0, mi::Int64=0, s::Int64=0,
                      ms::Int64=0, us::Int64=0, ns::Int64=0, ampm::Dates.AMPM=Dates.TWENTYFOURHOUR) where {P}
    err = Dates.validargs(Timestamp{P}, y, m, d, h, mi, s, ms, us, ns, ampm)
    err === nothing || throw(err)
    h = Dates.adjusthour(h, ampm)
    nsofday = ns + 1000us + 1000000ms + 1000000000 * (s + 60mi + 3600h)
    return timestamp_from_day(Timestamp{P}, Dates.totaldays(y, m, d), nsofday)
end

function Dates.validargs(::Type{Timestamp{P}}, y::Int64, m::Int64, d::Int64, h::Int64, mi::Int64,
                         s::Int64, ms::Int64, us::Int64, ns::Int64, ampm::Dates.AMPM=Dates.TWENTYFOURHOUR) where {P}
    year(typemin(Timestamp{P})) <= y <= year(typemax(Timestamp{P})) ||
        return ArgumentError("Year: $y out of range for Timestamp{$(nameof(P))}")
    0 < m < 13 || return ArgumentError("Month: $m out of range (1:12)")
    0 < d < Dates.daysinmonth(y, m) + 1 || return ArgumentError("Day: $d out of range (1:$(Dates.daysinmonth(y, m)))")
    if ampm == Dates.TWENTYFOURHOUR # 24-hour clock
        -1 < h < 24 || (h == 24 && mi==s==ms==us==ns==0) ||
            return ArgumentError("Hour: $h out of range (0:23)")
    else
        0 < h < 13 || return ArgumentError("Hour: $h out of range (1:12)")
    end
    -1 < mi < 60 || return ArgumentError("Minute: $mi out of range (0:59)")
    -1 < s < 60 || return ArgumentError("Second: $s out of range (0:59)")
    -1 < ms < 1000 || return ArgumentError("Millisecond: $ms out of range (0:999)")
    -1 < us < 1000 || return ArgumentError("Microsecond: $us out of range (0:999)")
    -1 < ns < 1000000000 || return ArgumentError("Nanosecond: $ns out of range (0:999999999)")
    1000000ms + 1000us + ns < 1000000000 ||
        return ArgumentError("Sub-second parts must together be less than one second")
    epochdays = Dates.totaldays(y, m, d) - UNIXEPOCHDAYS
    nsofday = ns + 1000us + 1000000ms + 1000000000 * (s + 60mi + 3600 * Dates.adjusthour(h, ampm))
    ticks, remainder = divrem(nsofday, timestamp_scale(P))
    iszero(remainder) || return ArgumentError("Fractional second is not exactly representable as Timestamp{$(nameof(P))}")
    fldmod(typemin(Int64), timestamp_ticks_per_day(P)) <= (epochdays, ticks) <=
        fldmod(typemax(Int64), timestamp_ticks_per_day(P)) ||
        return timestamp_range_error(P, y, m, d)
    return nothing
end

# The messages name the resolution and the bounds with plain integers and symbols, in
# short `string` calls: interpolating a `Timestamp` or a type prints through dynamic
# dispatch, and a `string` of more than about ten pieces is compiled with `Vararg{Any}`;
# a `--trim=safe` build rejects both.
@noinline function timestamp_range_error(::Type{P}, y::Int64, m::Int64, d::Int64) where {P}
    lo, hi = typemin(Timestamp{P}), typemax(Timestamp{P})
    return ArgumentError(string("Timestamp: ", ymd(y, m, d), " out of range for Timestamp{", nameof(P), "} (", ymd(lo), " to ", ymd(hi), ")"))
end

ymd(y::Int64, m::Int64, d::Int64) = string(y, '-', m, '-', d)
ymd(ts::Timestamp) = ymd(Dates.year(ts), Dates.month(ts), Dates.day(ts))

Dates.validargs(::Type{Timestamp}, args...) = Dates.validargs(Timestamp{Nanosecond}, args...)

function Timestamp{P}(y::Year, m::Month=Month(1), d::Day=Day(1),
                      h::Hour=Hour(0), mi::Minute=Minute(0), s::Second=Second(0),
                      ms::Millisecond=Millisecond(0),
                      us::Microsecond=Microsecond(0), ns::Nanosecond=Nanosecond(0)) where {P}
    return Timestamp{P}(value(y), value(m), value(d), value(h), value(mi), value(s),
                        value(ms), value(us), value(ns))
end

"""
    Timestamp(periods::Period...)::Timestamp

Construct a `Timestamp` type by `Period` type parts. Arguments may be in any order.
`Timestamp` parts not provided will default to the unix epoch, `1970-01-01T00:00:00`.
"""
function Timestamp{P}(period::Period, periods::Period...) where {P}
    y = Year(1970); m = Month(1); d = Day(1)
    h = Hour(0); mi = Minute(0); s = Second(0)
    ms = Millisecond(0); us = Microsecond(0); ns = Nanosecond(0)
    for p in (period, periods...)
        isa(p, Year) && (y = p::Year)
        isa(p, Month) && (m = p::Month)
        isa(p, Day) && (d = p::Day)
        isa(p, Hour) && (h = p::Hour)
        isa(p, Minute) && (mi = p::Minute)
        isa(p, Second) && (s = p::Second)
        isa(p, Millisecond) && (ms = p::Millisecond)
        isa(p, Microsecond) && (us = p::Microsecond)
        isa(p, Nanosecond) && (ns = p::Nanosecond)
    end
    return Timestamp{P}(y, m, d, h, mi, s, ms, us, ns)
end

"""
    Timestamp(d::Date, [t::Time])::Timestamp

Construct a `Timestamp` from a `Date` and, optionally, a `Time` giving the
time of day. Throws an `ArgumentError` if the result lies outside the
representable range, or an `InexactError` if the time of day is not
representable at resolution `P`.
"""
function Timestamp{P}(d::Date, t::Time=Time(0)) where {P}
    ticks, remainder = divrem(value(t), timestamp_scale(P))
    iszero(remainder) || throw(InexactError(:convert, Timestamp{P}, t))
    epochdays = Int128(value(d)) - UNIXEPOCHDAYS
    typemin(Int64) <= epochdays * timestamp_ticks_per_day(P) + ticks <= typemax(Int64) ||
        throw(ArgumentError("Date out of range for Timestamp{$P}"))
    return timestamp_from_day(Timestamp{P}, value(d), value(t))
end

# Fallback constructor
Timestamp{P}(y, m=1, d=1, h=0, mi=0, s=0, ms=0, us=0, ns=0, ampm::Dates.AMPM=Dates.TWENTYFOURHOUR) where {P} =
    Timestamp{P}(Int64(y), Int64(m), Int64(d), Int64(h), Int64(mi), Int64(s), Int64(ms), Int64(us), Int64(ns), ampm)

### Traits, equality, hashing

Dates.calendar(dt::Timestamp) = Dates.ISOCalendar

Base.eps(::Type{Timestamp}) = Nanosecond(1)
Base.eps(::Type{Timestamp{P}}) where {P} = P(1)
Base.zero(::Type{Timestamp}) = Nanosecond(0)
Base.zero(::Type{Timestamp{P}}) where {P} = P(0)

Base.typemax(::Type{Timestamp}) = typemax(Timestamp{Nanosecond})
Base.typemax(::Type{Timestamp{P}}) where {P} = Timestamp{P}(UTInstant(P(typemax(Int64))))
Base.typemax(x::Timestamp) = typemax(typeof(x))
Base.typemin(::Type{Timestamp}) = typemin(Timestamp{Nanosecond})
Base.typemin(::Type{Timestamp{P}}) where {P} = Timestamp{P}(UTInstant(P(typemin(Int64))))
Base.typemin(x::Timestamp) = typemin(typeof(x))

Base.promote_rule(::Type{Date}, ::Type{Timestamp{P}}) where {P} = Timestamp{P}
Base.promote_rule(::Type{DateTime}, ::Type{Timestamp{P}}) where {P} = Timestamp{timestamp_finer(P, Millisecond)}
Base.promote_rule(::Type{Timestamp{P}}, ::Type{Timestamp{Q}}) where {P,Q} = Timestamp{timestamp_finer(P, Q)}

Base.isless(x::Timestamp, y::Timestamp) = isless((days(x), nsofday(x)), (days(y), nsofday(y)))
Base.:(==)(x::Timestamp, y::Timestamp) = days(x) == days(y) && nsofday(x) == nsofday(y)
Base.isless(x::T, y::T) where {T<:Timestamp} = isless(value(x), value(y))
Base.:(==)(x::T, y::T) where {T<:Timestamp} = value(x) == value(y)

# Comparisons between Timestamp and the wider-ranged Date/DateTime bypass
# promotion (which would throw for instants outside the Timestamp range) and
# instead compare (day, time-of-day) pairs, which never overflow.
msofday(dt::DateTime) = mod(value(dt), 86400000)
Base.isless(x::Timestamp, y::DateTime) = isless((days(x), nsofday(x)), (days(y), 1000000 * msofday(y)))
Base.isless(x::DateTime, y::Timestamp) = isless((days(x), 1000000 * msofday(x)), (days(y), nsofday(y)))
Base.isless(x::Timestamp, y::Date) = isless((days(x), nsofday(x)), (value(y), Int64(0)))
Base.isless(x::Date, y::Timestamp) = isless((value(x), Int64(0)), (days(y), nsofday(y)))
Base.:(==)(x::Timestamp, y::DateTime) = days(x) == days(y) && nsofday(x) == 1000000 * msofday(y)
Base.:(==)(x::DateTime, y::Timestamp) = y == x
Base.:(==)(x::Timestamp, y::Date) = days(x) == value(y) && nsofday(x) == 0
Base.:(==)(x::Date, y::Timestamp) = y == x

# The stdlib implementation hashes Date, DateTime, and Timestamp alike on the
# (day, nanosecond of day) pair. This shim cannot redefine the stdlib's
# Date/DateTime hashes, so it hashes a Timestamp like the equal DateTime when
# one exists, keeping `hash` consistent with `==` for DateTime keys and across
# Timestamp resolutions. Equal Date and Timestamp values hash differently here,
# exactly as equal Date and DateTime values do in these Julia versions.
const DATETIME_DAY_LIMIT = typemax(Int64) ÷ 86400000 - 1
function Base.hash(x::Timestamp, h::UInt)
    d, ns = days(x), nsofday(x)
    if iszero(ns % 1000000) && -DATETIME_DAY_LIMIT <= d <= DATETIME_DAY_LIMIT
        return hash(DateTime(Dates.UTM(d * 86400000 + ns ÷ 1000000)), h)
    end
    return hash(ns, hash(d, hash(:Timestamp, h)))
end

### Accessors

Dates.days(dt::Timestamp{P}) where {P} = fld(value(dt), timestamp_ticks_per_day(P)) + UNIXEPOCHDAYS
nsofday(dt::Timestamp{P}) where {P} = mod(value(dt), timestamp_ticks_per_day(P)) * timestamp_scale(P)

@inline timestamp_part(dt::Timestamp{P}, unit, modulus) where {P} =
    unit < timestamp_scale(P) ? Int64(0) :
    mod(fld(value(dt), unit ÷ timestamp_scale(P)), modulus)
Dates.hour(dt::Timestamp) = timestamp_part(dt, 3600000000000, Int64(24))
Dates.minute(dt::Timestamp) = timestamp_part(dt, 60000000000, Int64(60))
Dates.second(dt::Timestamp) = timestamp_part(dt, Int64(1000000000), Int64(60))
Dates.millisecond(dt::Timestamp) = timestamp_part(dt, Int64(1000000), Int64(1000))
Dates.microsecond(dt::Timestamp) = timestamp_part(dt, Int64(1000), Int64(1000))
Dates.nanosecond(dt::Timestamp) = timestamp_part(dt, Int64(1), Int64(1000))

for (period, accessor) in ((:Year, :year), (:Quarter, :quarter), (:Month, :month), (:Week, :week), (:Day, :day),
                           (:Hour, :hour), (:Minute, :minute), (:Second, :second), (:Millisecond, :millisecond),
                           (:Microsecond, :microsecond), (:Nanosecond, :nanosecond))
    @eval Dates.$period(dt::Timestamp) = Dates.$period(Dates.$accessor(dt))
end

@static if isdefined(Dates, :isoyear)
    function Dates.isoyear(dt::Timestamp)
        thisyear = Year(dt)
        thismonth = Month(dt)
        weeknumber = week(dt)
        if weeknumber >= 52 && thismonth.value == 1
            return Year(thisyear.value - 1)
        elseif weeknumber == 1 && thismonth.value == 12
            return Year(thisyear.value + 1)
        else
            return thisyear
        end
    end
    Dates.isoweekdate(dt::Timestamp) = (Dates.isoyear(dt).value, week(dt), dayofweek(dt))
end

### Conversions

"""
    Timestamp{P}(dt::TimeType)

Convert a `Date`, `DateTime`, or `Timestamp` to `Timestamp{P}`. The instant must
be exactly representable at resolution `P`. A precision loss or out-of-range
`DateTime` or `Timestamp` throws an `InexactError`; an out-of-range
`Date` throws an `ArgumentError`.
"""
Timestamp{P}(dt::TimeType) where {P} = convert(Timestamp{P}, dt)
Base.convert(::Type{Timestamp}, dt::Union{Date,DateTime}) = convert(Timestamp{Nanosecond}, dt)
Base.convert(::Type{Timestamp}, dt::Timestamp) = dt
Base.convert(::Type{Timestamp{P}}, dt::Timestamp{P}) where {P} = dt
function Base.convert(::Type{Timestamp{P}}, dt::Timestamp{Q}) where {P,Q}
    return Timestamp{P}(UTInstant(P(timestamp_ticks(P, Int128(value(dt)) * timestamp_scale(Q)))))
end

# DateTime -> Timestamp throws an InexactError for instants outside the
# Timestamp range; Timestamp -> DateTime floors to the millisecond.
function Base.convert(::Type{Timestamp{P}}, dt::DateTime) where {P}
    ticks = timestamp_ticks(P, (Int128(value(dt)) - Dates.UNIXEPOCH) * 1000000)
    return Timestamp{P}(UTInstant(P(ticks)))
end
Base.convert(::Type{Timestamp{P}}, dt::Date) where {P} = Timestamp{P}(dt)
Base.convert(::Type{DateTime}, dt::Timestamp{P}) where {P} =
    DateTime(Dates.UTM(Int64(fld(Int128(value(dt)) * timestamp_scale(P), 1000000) + Dates.UNIXEPOCH)))
Base.convert(::Type{Date}, dt::Timestamp) = Date(Dates.UTD(days(dt)))
Base.convert(::Type{Time}, dt::Timestamp) = Time(Nanosecond(nsofday(dt)))
# `Date(::TimeType)` and `DateTime(::TimeType)` already dispatch to `convert`;
# `Time` only accepts `DateTime` before Julia 1.14.
Dates.Time(dt::Timestamp) = convert(Time, dt)

# Raw Unix counts, rather than calendar components.
Base.convert(::Type{Timestamp}, x::Nanosecond) = Timestamp(UTInstant(x))
Base.convert(::Type{P}, dt::Timestamp{Q}) where {P<:Union{Second,Millisecond,Microsecond,Nanosecond},Q} =
    P(timestamp_ticks(P, Int128(value(dt)) * timestamp_scale(Q)))
Base.convert(::Type{Timestamp{P}}, x::Q) where {P,Q<:Union{Second,Millisecond,Microsecond,Nanosecond}} =
    Timestamp{P}(UTInstant(P(timestamp_ticks(P, Int128(value(x)) * timestamp_scale(Q)))))

"""
    unix2timestamp(x)::Timestamp
    unix2timestamp(Timestamp{P}, x)::Timestamp{P}

Take the number of seconds since unix epoch `1970-01-01T00:00:00` (UTC) and
convert to the corresponding `Timestamp`, optionally at resolution `P`.
Fractional input is truncated toward zero to units of `P`.
Note that a `Float64` second count near the present carries only about
microsecond precision; construct a `Timestamp` from an integer nanosecond count
(`convert(Timestamp, Nanosecond(ns))`) when full nanosecond precision is
required.
"""
unix2timestamp(x::Real) = unix2timestamp(Timestamp{Nanosecond}, x)
unix2timestamp(::Type{Timestamp}, x::Real) = unix2timestamp(Timestamp{Nanosecond}, x)
unix2timestamp(::Type{Timestamp{P}}, x::Real) where {P} =
    Timestamp{P}(UTInstant(P(trunc(Int64, (1000000000 ÷ timestamp_scale(P)) * x))))
function unix2timestamp(::Type{Timestamp{P}}, x::Integer) where {P}
    scale = 1000000000 ÷ timestamp_scale(P)
    cld(typemin(Int64), scale) <= x <= fld(typemax(Int64), scale) ||
        throw(InexactError(:unix2timestamp, Timestamp{P}, x))
    return Timestamp{P}(UTInstant(P(Int64(x) * scale)))
end

"""
    timestamp2unix(dt::Timestamp)::Float64

Take the given `Timestamp` and return the number of seconds since the unix
epoch `1970-01-01T00:00:00` as a `Float64`. Note that the returned value
carries only about microsecond precision near the present; `Dates.value(dt)`
is the exact count in the timestamp's resolution since the unix epoch.
"""
timestamp2unix(dt::Timestamp{P}) where {P} = value(dt) / (1000000000 ÷ timestamp_scale(P))

# Wall clock as (seconds, nanoseconds) since the Unix epoch. The stdlib uses
# libuv's uv_clock_gettime, which older bundled libuv builds do not export.
@static if Sys.iswindows()
    function unix_now_ns()
        filetime = Ref{UInt64}(0)
        ccall((:GetSystemTimePreciseAsFileTime, "kernel32"), stdcall, Cvoid, (Ref{UInt64},), filetime)
        # 100-nanosecond intervals since 1601-01-01, shifted to the Unix epoch
        ticks = Int64(filetime[]) - Int64(116444736000000000)
        sec, rem = fldmod(ticks, Int64(10000000))
        return sec, rem * 100
    end
else
    struct TimeSpec
        sec::Clong
        nsec::Clong
    end
    function unix_now_ns()
        ts = Ref{TimeSpec}()
        # 0 is CLOCK_REALTIME on Linux, macOS, and the BSDs
        err = ccall(:clock_gettime, Cint, (Cint, Ref{TimeSpec}), 0, ts)
        err == 0 || throw(SystemError("clock_gettime"))
        return Int64(ts[].sec), Int64(ts[].nsec)
    end
end

"""
    now(::Type{Timestamp})::Timestamp
    now(::Type{Timestamp{P}})::Timestamp{P}

Return a `Timestamp` corresponding to the user's system time including the
system timezone locale. With a specified resolution `P`, fractional seconds
are floored to that resolution. The default uses nanoseconds.
"""
Dates.now(::Type{Timestamp}) = Dates.now(Timestamp{Nanosecond})
function Dates.now(::Type{Timestamp{P}}) where {P}
    sec, nsec = unix_now_ns()
    tm = Base.Libc.TmStruct(sec)
    return Timestamp{P}(tm.year + 1900, tm.month + 1, tm.mday, tm.hour, tm.min, tm.sec,
                        0, 0, fld(nsec, timestamp_scale(P)) * timestamp_scale(P))
end

"""
    now(::Type{Timestamp}, ::Type{UTC})::Timestamp
    now(::Type{Timestamp{P}}, ::Type{UTC})::Timestamp{P}

Return a `Timestamp` corresponding to the user's system time as UTC/GMT.
With a specified resolution `P`, fractional seconds are floored to that
resolution. The default uses nanoseconds.
"""
Dates.now(::Type{Timestamp}, ::Type{UTC}) = Dates.now(Timestamp{Nanosecond}, UTC)
function Dates.now(::Type{Timestamp{P}}, ::Type{UTC}) where {P}
    sec, nsec = unix_now_ns()
    return Timestamp{P}(UTInstant(P(sec * (1000000000 ÷ timestamp_scale(P)) + fld(nsec, timestamp_scale(P)))))
end

### Arithmetic

# Fixed-duration arithmetic preserves resolution and wraps in units of P.
function timestamp_period_ticks(::Type{P}, y::FixedPeriod) where {P}
    unit, scale = Dates.tons(oneunit(y)), timestamp_scale(P)
    unit >= scale && return value(y) * (unit ÷ scale)
    ticks, remainder = divrem(value(y), scale ÷ unit)
    iszero(remainder) || throw(InexactError(:convert, P, y))
    return ticks
end
for op in (:+, :-)
    @eval begin
        Base.$op(x::Timestamp{P}, y::Union{Year,Quarter,Month}) where {P} =
            Timestamp{P}(UTInstant(P(((Int128(value(Base.$op(Date(x), y))) - UNIXEPOCHDAYS) *
                timestamp_ticks_per_day(P) + nsofday(x) ÷ timestamp_scale(P)) % Int64)))
        Base.$op(x::Timestamp{P}, y::FixedPeriod) where {P} =
            Timestamp{P}(UTInstant(P(Base.$op(value(x), timestamp_period_ticks(P, y)))))
    end
end

### Rounding

# Keep rounding candidates wide; only the requested result must fit.
function timestamp_rounding_value(dt::Timestamp{P}, ns, op::Symbol) where {P}
    ticks, remainder = divrem(ns, timestamp_scale(P))
    iszero(remainder) && typemin(Int64) <= ticks <= typemax(Int64) ||
        throw(InexactError(op, Timestamp{P}, dt))
    return Timestamp{P}(UTInstant(P(Int64(ticks))))
end

# Ordinary calendar years use Int64 arithmetic. Large rounding intervals can
# place a candidate outside even Date's range, so retain a wide fallback.
@inline function timestamp_rounding_days(y, m)
    if typemin(Int64) ÷ 366 + 1 <= y <= typemax(Int64) ÷ 366 - 1
        return Int128(Dates.totaldays(Int64(y), Int64(m), 1))
    end
    return Dates.totaldays(Int128(y), m, 1)
end

@inline function timestamp_month_bounds(dt::Timestamp, months, step, upper::Bool)
    lower = months - mod(months, step)
    fy, fm = fldmod(lower, 12)
    f = (timestamp_rounding_days(fy, fm + 1) - UNIXEPOCHDAYS) * NS_PER_DAY
    upper || return f, f
    x = Int128(value(dt)) * timestamp_scale(typeof(dt))
    x == f && return f, f
    cy, cm = fldmod(lower + step, 12)
    c = (timestamp_rounding_days(cy, cm + 1) - UNIXEPOCHDAYS) * NS_PER_DAY
    return f, c
end

@inline function timestamp_rounding_bounds(dt::Timestamp, p::Union{Year,Quarter,Month}, upper::Bool)
    value(p) < 1 && throw(DomainError(p))
    y, m = yearmonth(dt)
    months = 12y + m - 1
    step = Int128(value(p)) * (p isa Year ? 12 : p isa Quarter ? 3 : 1)
    # Timestamp month counts have magnitude below 4e12. If step fits Int64,
    # the adjacent multiples fit too; Year and Quarter can require a wider step.
    if step <= typemax(Int64)
        return timestamp_month_bounds(dt, months, Int64(step), upper)
    end
    return timestamp_month_bounds(dt, Int128(months), step, upper)
end

@inline function timestamp_rounding_bounds(dt::Timestamp, p::FixedPeriod, upper::Bool)
    value(p) < 1 && throw(DomainError(p))
    epoch = p isa Week ? Dates.WEEKEPOCH : Dates.DATEEPOCH
    epochns = Int128(UNIXEPOCHDAYS - epoch) * NS_PER_DAY
    x = Int128(value(dt)) * timestamp_scale(typeof(dt))
    step = Int128(value(p)) * Dates.tons(oneunit(p))
    f = x - mod(x + epochns, step)
    return f, !upper || x == f ? f : f + step
end

Base.floor(dt::Timestamp, p::Period) =
    timestamp_rounding_value(dt, first(timestamp_rounding_bounds(dt, p, false)), :floor)
Base.ceil(dt::Timestamp, p::Period) =
    timestamp_rounding_value(dt, last(timestamp_rounding_bounds(dt, p, true)), :ceil)
function Dates.floorceil(dt::Timestamp, p::Period)
    f, c = timestamp_rounding_bounds(dt, p, true)
    return timestamp_rounding_value(dt, f, :floor), timestamp_rounding_value(dt, c, :ceil)
end
function Base.round(dt::Timestamp, p::Period, ::RoundingMode{:NearestTiesUp})
    f, c = timestamp_rounding_bounds(dt, p, true)
    x = Int128(value(dt)) * timestamp_scale(typeof(dt))
    return timestamp_rounding_value(dt, x - f < c - x ? f : c, :round)
end

Base.trunc(dt::Timestamp, ::Type{P}) where {P<:Period} = floor(dt, oneunit(P))

### Adjusters

for f in (:firstdayofweek, :lastdayofweek, :firstdayofmonth, :lastdayofmonth,
          :firstdayofyear, :lastdayofyear, :firstdayofquarter, :lastdayofquarter)
    @eval Dates.$f(dt::T) where {T<:Timestamp} = T(Dates.$f(Date(dt)))
end

"""
    Timestamp(f::Function, y, m=1; step=Day(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d; step=Hour(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d, h; step=Minute(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d, h, mi; step=Second(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d, h, mi, s; step=Millisecond(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d, h, mi, s, ms; step=Microsecond(1), limit=10000)::Timestamp
    Timestamp(f::Function, y, m, d, h, mi, s, ms, us; step=Nanosecond(1), limit=10000)::Timestamp

Create a `Timestamp` through the adjuster API. The starting point will be constructed from
the provided `y, m, d...` arguments, and will be adjusted until `f::Function` returns
`true`. The step size in adjusting can be provided manually through the `step` keyword.
`limit` provides a limit to the max number of iterations the adjustment API will
pursue before throwing an error (in the case that `f::Function` is never satisfied).
The default step is `Day(1)` when only a year or month is supplied. Each
additional part changes the default to the next finer unit, down to the
resolution of the `Timestamp`.
"""
Timestamp(::Function, args...)

function Timestamp{P}(func::Function, y, m=1; step::Period=Day(1), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m); step, limit)
end
function Timestamp{P}(func::Function, y, m, d; step::Period=Hour(1), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d); step, limit)
end
function Timestamp{P}(func::Function, y, m, d, h; step::Period=Minute(1), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d, h); step, limit)
end
function Timestamp{P}(func::Function, y, m, d, h, mi; step::Period=Second(1), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d, h, mi); step, limit)
end
function Timestamp{P}(func::Function, y, m, d, h, mi, s; step::Period=max(Millisecond(1), eps(Timestamp{P})), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d, h, mi, s); step, limit)
end
function Timestamp{P}(func::Function, y, m, d, h, mi, s, ms; step::Period=max(Microsecond(1), eps(Timestamp{P})), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d, h, mi, s, ms); step, limit)
end
function Timestamp{P}(func::Function, y, m, d, h, mi, s, ms, us; step::Period=max(Nanosecond(1), eps(Timestamp{P})), limit::Int=10000) where {P}
    return Dates.adjust(func, Timestamp{P}(y, m, d, h, mi, s, ms, us); step, limit)
end

### Ranges

Dates.guess(a::Timestamp, b::Timestamp, c) =
    floor(Int64, div(Int128(value(b)) * timestamp_scale(typeof(b)) - Int128(value(a)) * timestamp_scale(typeof(a)),
                     Int128(value(c)) * Dates.tons(oneunit(c))))
Base.length(r::StepRange{<:Timestamp}) = isempty(r) ? Int64(0) :
    Base.Checked.checked_add(Dates.len(r.start, r.stop, r.step), Int64(1))

### Parsing and formatting: the `n` fractional-second code

# Register the `n` code and the Timestamp token order with Dates. These are
# mutations of Dates globals, so they run both at load time (for precompiled
# constants below) and again from `__init__` in every session.
const TIMESTAMP_TOKENS = (Year, Month, Day, Hour, Minute, Second, Millisecond, Microsecond, Nanosecond, Dates.AMPM)
function register_dates_hooks!()
    Dates.CONVERSION_SPECIFIERS['n'] = Nanosecond
    for T in (Timestamp, Timestamp{Second}, Timestamp{Millisecond}, Timestamp{Microsecond}, Timestamp{Nanosecond})
        Dates.CONVERSION_TRANSLATIONS[T] = TIMESTAMP_TOKENS
    end
    return nothing
end
register_dates_hooks!()

@inline function tryparsenext_fraction(d::Dates.DatePart, str, i, len, precision)
    digits = 0
    val = Int64(0)
    max_digits = Dates.max_width(d)
    @inbounds while i <= len && (max_digits == 0 || digits < max_digits)
        c, ii = iterate(str, i)::Tuple{Char, Int}
        '0' <= c <= '9' || break
        digit = Int64(c - '0')
        digits += 1
        if digits <= precision
            val = 10val + digit
        elseif digit != 0
            return nothing
        end
        i = ii
    end
    digits >= Dates.min_width(d) || return nothing
    digits < precision && (val *= Int64(10) ^ (precision - digits))
    return val, i
end

# Reads the digits as a fractional second down to nanosecond resolution: ".5"
# is 500 milliseconds and ".123456789" is 123456789 nanoseconds. Digits past
# the ninth must be zero.
@inline function Dates.tryparsenext(d::Dates.DatePart{'n'}, str, i, len)
    return tryparsenext_fraction(d, str, i, len, 9)
end

function format_fraction(io, d::Dates.DatePart, val, precision)
    str = rstrip(string(val, pad = precision), '0')
    if d.fixed && length(str) > d.width
        str = SubString(str, 1, d.width)
    end
    print(io, rpad(str, d.width, '0'))
    return nothing
end

# The fractional second with trailing zeros stripped, then zero-padded on the
# right to the code's width: 500 milliseconds formats as "5" under `n` and as
# "500000000" under `nnnnnnnnn`; both parse back to the same value.
function Dates.format(io, d::Dates.DatePart{'n'}, dt)
    format_fraction(io, d, subsecond_nanoseconds(dt), 9)
    return nothing
end

subsecond_nanoseconds(dt::DateTime) = 1000000 * millisecond(dt)
subsecond_nanoseconds(dt::Time) =
    1000000 * millisecond(dt) + 1000 * microsecond(dt) + nanosecond(dt)
subsecond_nanoseconds(dt::Timestamp{P}) where {P} =
    mod(value(dt), 1000000000 ÷ timestamp_scale(P)) * timestamp_scale(P)

"""
    ISOTimestampFormat

Describes the ISO8601 formatting for a date and time at nanosecond resolution.
This is the default value for `Dates.format` of a `Timestamp`. The fractional
second is written with trailing zeros stripped and parsed with up to nanosecond
precision.
"""
const ISOTimestampFormat = DateFormat("yyyy-mm-dd\\THH:MM:SS.n")
Dates.default_format(::Type{<:Timestamp}) = ISOTimestampFormat

"""
    Timestamp(dt::AbstractString, format::AbstractString; locale="english")::Timestamp

Construct a `Timestamp` by parsing the `dt` date time string following the
pattern given in the `format` string (see `Dates.DateFormat` for syntax).
Use the `n` code to match fractional seconds with up to nanosecond precision.
"""
function Timestamp{P}(dt::AbstractString, format::AbstractString; locale::Dates.Locale=Dates.ENGLISH) where {P}
    return parse(Timestamp{P}, dt, DateFormat(format, locale))
end

"""
    Timestamp(dt::AbstractString, df::DateFormat=ISOTimestampFormat)::Timestamp

Construct a `Timestamp` by parsing the `dt` date time string following the
pattern given in the `DateFormat` object, or `ISOTimestampFormat` if omitted.
"""
Timestamp{P}(dt::AbstractString, df::DateFormat=ISOTimestampFormat) where {P} = parse(Timestamp{P}, dt, df)

const PRINT_FORMAT = DateFormat("YYYY-mm-dd\\THH:MM:SS")
const PRINT_FORMAT_FRACTION = DateFormat("YYYY-mm-dd\\THH:MM:SS.n")

function Base.print(io::IO, dt::Timestamp)
    str = if subsecond_nanoseconds(dt) == 0
        Dates.format(dt, PRINT_FORMAT, 19)
    else
        Dates.format(dt, PRINT_FORMAT_FRACTION, 29)
    end
    print(io, str)
    return nothing
end

Base.show(io::IO, ::MIME"text/plain", dt::Timestamp) = print(io, dt)
Base.show(io::IO, dt::Timestamp) = print(io, typeof(dt), "(\"", dt, "\")")
Base.typeinfo_implicit(::Type{<:Timestamp}) = true

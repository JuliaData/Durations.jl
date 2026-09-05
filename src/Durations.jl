"""
    Durations

Fixed-width calendar intervals with independent month, day, and nanosecond
components. `Duration` matches Arrow's 16-byte MONTH_DAY_NANO interval layout.
"""
module Durations

import Dates

export Duration

"""
    Duration(months::Integer, days::Integer, nanoseconds::Integer)
    Duration(; months=0, days=0, nanoseconds=0)
    Duration(period::Dates.Period)
    Duration(period::Dates.CompoundPeriod)

A 16-byte value with `months::Int32`, `days::Int32`, and `nanoseconds::Int64`,
in that order. Each component is independent and may have either sign.
Construction and arithmetic check bounds. Components are never normalized:
one month is not a fixed number of days, and a calendar day is not always
24 hours. Equality and hashing compare the three stored components.

Convert to `Dates.CompoundPeriod` explicitly for calendar operations. There
is no context-free ordering or conversion to a single elapsed-time count.
"""
struct Duration
    months::Int32
    days::Int32
    nanoseconds::Int64
    function Duration(months::Integer, days::Integer, nanoseconds::Integer)
        return new(Int32(months), Int32(days), Int64(nanoseconds))
    end
end

Duration(; months::Integer=0, days::Integer=0, nanoseconds::Integer=0) =
    Duration(months, days, nanoseconds)
Duration(x::Duration) = x
Base.convert(::Type{Duration}, x::Duration) = x
Base.broadcastable(x::Duration) = Ref(x)
Base.zero(::Type{Duration}) = Duration(0, 0, 0)
Base.zero(::Duration) = zero(Duration)
Base.iszero(x::Duration) = iszero(x.months) && iszero(x.days) && iszero(x.nanoseconds)
Base.:(==)(x::Duration, y::Duration) =
    x.months == y.months && x.days == y.days && x.nanoseconds == y.nanoseconds
Base.isequal(x::Duration, y::Duration) = x == y
Base.hash(x::Duration, h::UInt) = hash(x.nanoseconds, hash(x.days, hash(x.months, hash(:Duration, h))))

function Base.:+(x::Duration, y::Duration)
    return Duration(Base.checked_add(x.months, y.months),
                    Base.checked_add(x.days, y.days),
                    Base.checked_add(x.nanoseconds, y.nanoseconds))
end

function Base.:-(x::Duration, y::Duration)
    return Duration(Base.checked_sub(x.months, y.months),
                    Base.checked_sub(x.days, y.days),
                    Base.checked_sub(x.nanoseconds, y.nanoseconds))
end

Base.:+(x::Duration) = x
Base.:-(x::Duration) = Duration(Base.checked_neg(x.months), Base.checked_neg(x.days), Base.checked_neg(x.nanoseconds))

function _multiply(x::T, n::Integer) where {T<:Integer}
    iszero(x) && return zero(T)
    result = Base.checked_mul(Int128(x), Int128(n))
    typemin(T) <= result <= typemax(T) || throw(OverflowError("duration component multiplication overflow"))
    return T(result)
end

Base.:*(x::Duration, n::Integer) = Duration(_multiply(x.months, n), _multiply(x.days, n), _multiply(x.nanoseconds, n))
Base.:*(n::Integer, x::Duration) = x * n

function Base.show(io::IO, x::Duration)
    print(io, "Durations.Duration(", x.months, ", ", x.days, ", ", x.nanoseconds, ")")
    return nothing
end

_parts(x::Dates.Year) = (Int128(Dates.value(x)) * 12, Int128(0), Int128(0))
_parts(x::Dates.Quarter) = (Int128(Dates.value(x)) * 3, Int128(0), Int128(0))
_parts(x::Dates.Month) = (Int128(Dates.value(x)), Int128(0), Int128(0))
_parts(x::Dates.Week) = (Int128(0), Int128(Dates.value(x)) * 7, Int128(0))
_parts(x::Dates.Day) = (Int128(0), Int128(Dates.value(x)), Int128(0))
for (P, factor) in ((Dates.Hour, 3_600_000_000_000), (Dates.Minute, 60_000_000_000),
                    (Dates.Second, 1_000_000_000), (Dates.Millisecond, 1_000_000),
                    (Dates.Microsecond, 1_000), (Dates.Nanosecond, 1))
    @eval _parts(x::$P) = (Int128(0), Int128(0), Int128(Dates.value(x)) * $factor)
end

Duration(x::Dates.Period) = Duration(_parts(x)...)

function Duration(x::Dates.CompoundPeriod)
    months = days = nanos = Int128(0)
    for p in Dates.periods(x)
        m, d, n = _parts(p)
        months = Base.checked_add(months, m)
        days = Base.checked_add(days, d)
        nanos = Base.checked_add(nanos, n)
    end
    return Duration(months, days, nanos)
end

Base.convert(::Type{Duration}, x::Union{Dates.Period,Dates.CompoundPeriod}) = Duration(x)

function Dates.CompoundPeriod(x::Duration)
    return Dates.CompoundPeriod(Dates.Period[Dates.Month(x.months), Dates.Day(x.days), Dates.Nanosecond(x.nanoseconds)])
end

Base.convert(::Type{Dates.CompoundPeriod}, x::Duration) = Dates.CompoundPeriod(x)

end

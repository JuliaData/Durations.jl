# TimeZones.jl integration: rules for every zone name TimeZones knows, and conversions and
# comparisons between `ZonedTimestamp` and `ZonedDateTime`.
module DurationsTimeZonesExt

using Durations: Durations, ZonedTimestamp, Timestamp, ZoneRules
using Dates: Dates, DateTime, UTC
using TimeZones: TimeZones, TimeZone, FixedTimeZone, VariableTimeZone, ZonedDateTime, Class

function Durations.namedrules(name::Symbol)
    s = String(name)
    TimeZones.istimezone(s, Class(:ALL)) || return nothing
    return rules(name, TimeZone(s, Class(:ALL)))
end

seconds(dt::DateTime) = fld(Dates.value(dt) - Dates.UNIXEPOCH, 1000)
offset(z::FixedTimeZone) = Int64(Dates.value(z.offset))

rules(name::Symbol, tz::FixedTimeZone) = ZoneRules(name, offset(tz))
function rules(name::Symbol, tz::VariableTimeZone)
    t = tz.transitions
    # the first rule also covers all earlier times
    starts = Int64[i == 1 ? typemin(Int64) : seconds(t[i].utc_datetime) for i in eachindex(t)]
    until = tz.cutoff === nothing ? typemax(Int64) : seconds(tz.cutoff)
    return ZoneRules(name, starts, Int64[offset(x.zone) for x in t], until)
end

# The zone name for a TimeZones.jl zone. TimeZones names a fixed offset "UTC+07:30", and Arrow
# writes it "+07:30".
function zonesymbol(tz::TimeZone)
    name = String(TimeZones.name(tz))
    tz isa FixedTimeZone && occursin(r"^UTC[+-]", name) && return Symbol(chop(name; head=3, tail=0))
    return Symbol(name)
end

Durations.astimezone(zt::ZonedTimestamp{P}, tz::TimeZone) where {P} = ZonedTimestamp{P,zonesymbol(tz)}(zt)
TimeZones.astimezone(zt::ZonedTimestamp, zone::Union{TimeZone,Symbol,AbstractString}) = Durations.astimezone(zt, zone)
TimeZones.timezone(::ZonedTimestamp{P,Z}) where {P,Z} = TimeZone(String(Z), Class(:ALL))

ZonedTimestamp{P,Z}(zdt::ZonedDateTime) where {P,Z} = ZonedTimestamp{P,Z}(Timestamp{P}(DateTime(zdt, UTC)), UTC)
ZonedTimestamp{P}(zdt::ZonedDateTime) where {P} = ZonedTimestamp{P,zonesymbol(TimeZones.timezone(zdt))}(zdt)
ZonedTimestamp(zdt::ZonedDateTime) = ZonedTimestamp{Dates.Millisecond}(zdt)

# `ZonedDateTime` holds milliseconds, so finer times are floored, as `DateTime(ts)` does
TimeZones.ZonedDateTime(zt::ZonedTimestamp) =
    ZonedDateTime(DateTime(zt.utc), TimeZones.timezone(zt); from_utc=true)

Base.:(==)(x::ZonedTimestamp, y::ZonedDateTime) = x.utc == DateTime(y, UTC)
Base.:(==)(x::ZonedDateTime, y::ZonedTimestamp) = y == x
Base.isless(x::ZonedTimestamp, y::ZonedDateTime) = isless(x.utc, DateTime(y, UTC))
Base.isless(x::ZonedDateTime, y::ZonedTimestamp) = isless(DateTime(x, UTC), y.utc)

end

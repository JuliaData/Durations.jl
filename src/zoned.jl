# `ZonedTimestamp{P,Z}`: a UTC `Timestamp{P}` labeled with the time zone named `Z`.

using Dates: Dates, AbstractDateTime, Date, DateTime, Time, UTC, DatePeriod, TimePeriod,
    Second, Millisecond, Microsecond, Nanosecond

"""
    Durations.ZonedTimestamp{P,Z}

A point in time in a time zone. It stores one field, `utc::Timestamp{P}`, the time in
UTC, and names its time zone with the type parameter `Z`, a `Symbol` such as `:UTC`,
`Symbol("+07:30")`, or `Symbol("America/Denver")`.

`ZonedTimestamp{P,Z}(ts::Timestamp)` reads `ts` as local time in the zone, and
`ZonedTimestamp{P,Z}(ts, UTC)` reads it as UTC. `Timestamp{P}(zt)` and
`Timestamp{P}(zt, UTC)` convert back. `Durations.astimezone(zt, zone)` keeps the time
and changes the zone.

Comparison, hashing, subtraction, and adding a `TimePeriod` use only the UTC time, so
they work for any zone name. Local fields such as `hour` and `Date`, adding a
`DatePeriod`, and rounding need the zone's rules. Durations knows `"UTC"` and fixed
offsets of the form `"+HH:MM"` or `"-HH:MM"`. Loading TimeZones.jl adds the names it
knows.

```julia
julia> const Jakarta = Durations.ZonedTimestamp{Nanosecond, Symbol("+07:00")};

julia> zt = Jakarta(Timestamp(2026, 3, 8, 16, 0))
Durations.ZonedTimestamp{Nanosecond, Symbol("+07:00")}("2026-03-08T16:00:00+07:00[+07:00]")

julia> Timestamp(zt, UTC), hour(zt)
(Timestamp{Nanosecond}("2026-03-08T09:00:00"), 16)
```

# Extended help

A `ZonedTimestamp{P,Z}` has the same 8 bytes as its UTC `Timestamp{P}`, and every
`Int64` is a valid value. A `Vector{ZonedTimestamp{P,Z}}` has the same bytes as an Apache
Arrow `timestamp` column with unit `P` and time zone `String(Z)`, so buffers can be
reinterpreted in either direction.

When clocks go back, a local time occurs twice. Constructing from it throws an
[`Durations.AmbiguousTimeError`](@ref) unless `occurrence` is `1` (the earlier time) or
`2` (the later time). When clocks go forward, a local time does not occur, and
constructing from it throws a [`Durations.NonExistentTimeError`](@ref). Adding a
`DatePeriod` and rounding to a `DatePeriod` compute a local time, so they throw the same
errors.
"""
struct ZonedTimestamp{P<:Union{Second,Millisecond,Microsecond,Nanosecond},Z} <: AbstractDateTime
    utc::Timestamp{P}
    # One method on purpose: dispatch ranks `utc::Timestamp` above `utc::Timestamp{P}`, so an
    # outer method that converts the resolution would call itself.
    function ZonedTimestamp{P,Z}(utc::Timestamp, ::Type{UTC}) where {P,Z}
        Z isa Symbol && Z !== Symbol("") ||
            throw(ArgumentError("the time zone name must be a nonempty Symbol"))
        return new{P,Z}(Timestamp{P}(utc))
    end
end

ZonedTimestamp{P,Z}(zt::ZonedTimestamp) where {P,Z} = ZonedTimestamp{P,Z}(zt.utc, UTC)

"""
    Durations.zonename(zt::ZonedTimestamp)::String
    Durations.zonename(ZonedTimestamp{P,Z})::String

The name of the time zone, `String(Z)`.
"""
zonename(::Type{ZonedTimestamp{P,Z}}) where {P,Z} = String(Z)
zonename(zt::ZonedTimestamp) = zonename(typeof(zt))

"""
    Durations.astimezone(zt::ZonedTimestamp, zone)::ZonedTimestamp

The same time in the time zone named `zone`, a `Symbol` or string.
"""
astimezone(zt::ZonedTimestamp{P}, zone::Union{Symbol,AbstractString}) where {P} =
    ZonedTimestamp{P,Symbol(zone)}(zt)

### Zone rules

"""
    Durations.ZoneRules(name::Symbol, starts::Vector{Int64}, offsets::Vector{Int64}, until::Int64)

The UTC offsets of the time zone `name`. Rule `i` applies from UTC second `starts[i]` (a
count of seconds since the Unix epoch) until the next rule starts; local time is UTC time
plus `offsets[i]` seconds. `starts[1]` must be `typemin(Int64)`. No rule applies at or after
UTC second `until`; `typemax(Int64)` means the rules have no end.
"""
mutable struct ZoneRules  # never mutated; a reference so that the cache can swap it atomically
    const name::Symbol
    const starts::Vector{Int64}
    const offsets::Vector{Int64}
    const until::Int64
    const localstarts::Vector{Int64}  # the local second at which each rule starts
    function ZoneRules(name::Symbol, starts::Vector{Int64}, offsets::Vector{Int64}, until::Int64)
        length(starts) == length(offsets) && !isempty(starts) && starts[1] == typemin(Int64) &&
            issorted(starts) || throw(ArgumentError("invalid time zone rules"))
        # a rule that ends where it starts never applies
        keep = Bool[i == length(starts) || starts[i] != starts[i + 1] for i in eachindex(starts)]
        s, o = starts[keep], offsets[keep]
        localstarts = Int64[i == 1 ? typemin(Int64) : s[i] + o[i] for i in eachindex(s)]
        issorted(localstarts) || throw(ArgumentError("invalid time zone rules"))
        return new(name, s, o, until, localstarts)
    end
end

ZoneRules(name::Symbol, offset::Int64) = ZoneRules(name, Int64[typemin(Int64)], Int64[offset], typemax(Int64))

inrange(r::ZoneRules, s::Int64) = r.until == typemax(Int64) || s < r.until

# The offset, in seconds, at UTC second `s`, or `nothing` past the end of the rules
ruleoffset(r::ZoneRules, s::Int64) = inrange(r, s) ? r.offsets[searchsortedlast(r.starts, s)] : nothing

# The rules under which local second `l` occurs: none in a gap, two in a fold
function localrules(r::ZoneRules, l::Int64)
    finish = searchsortedlast(r.localstarts, l)
    start = finish + 1
    while start > 1 && localend(r, start - 1) > l
        start -= 1
    end
    return start:finish
end

localend(r::ZoneRules, i::Int) = i == length(r.starts) ? typemax(Int64) : r.starts[i + 1] + r.offsets[i]

# "UTC" or a fixed offset "+HH:MM" or "-HH:MM", as Arrow writes them, in seconds
function fixedoffset(name::String)
    name == "UTC" && return Int64(0)
    b = codeunits(name)
    length(b) == 6 && b[1] in (UInt8('+'), UInt8('-')) && b[4] == UInt8(':') &&
        all(i -> UInt8('0') <= b[i] <= UInt8('9'), (2, 3, 5, 6)) || return nothing
    h = 10 * Int64(b[2] - UInt8('0')) + Int64(b[3] - UInt8('0'))
    m = 10 * Int64(b[5] - UInt8('0')) + Int64(b[6] - UInt8('0'))
    h <= 23 && m <= 59 || return nothing
    return b[1] == UInt8('-') ? -(3600h + 60m) : 3600h + 60m
end

# The rules for a time zone name other than "UTC" and fixed offsets, or `nothing` if the name
# is unknown. The TimeZones.jl extension adds the method.
function namedrules end

hastimezones() = Base.get_extension(@__MODULE__, :DurationsTimeZonesExt) !== nothing

mutable struct RulesCache
    @atomic rules::Dict{Symbol,ZoneRules}  # replaced on insert and never mutated, so reads need no lock
    # ponytail: one entry for runs of one zone; keep one per thread if loops over mixed zones get hot
    @atomic last::ZoneRules
end

const RULES = RulesCache(Dict{Symbol,ZoneRules}(), ZoneRules(:UTC, Int64(0)))
const RULES_LOCK = ReentrantLock()

# The rules for zone `name`, or `nothing` if they are unknown
function tryrules(name::Symbol)
    r = @atomic :acquire RULES.last
    r.name === name && return r
    r = get((@atomic :acquire RULES.rules), name, nothing)
    if r === nothing
        off = fixedoffset(String(name))
        if off !== nothing
            r = ZoneRules(name, off)
        else
            hastimezones() || return nothing
            r = namedrules(name)::Union{Nothing,ZoneRules}
            r === nothing && return nothing
        end
        @lock RULES_LOCK begin
            rules = copy(@atomic :acquire RULES.rules)
            rules[name] = r
            @atomic :release RULES.rules = rules
        end
    end
    @atomic :release RULES.last = r
    return r
end

function zonerules(name::Symbol)
    r = tryrules(name)
    r === nothing || return r
    hint = hastimezones() ? "" : "; Durations knows \"UTC\" and \"+HH:MM\" offsets, and TimeZones.jl adds other names"
    throw(ArgumentError(string("unknown time zone \"", String(name), "\"", hint)))
end

ticks_per_second(::Type{P}) where {P} = Dates.value(convert(P, Second(1)))

# `ts` plus `sign` times `offset` seconds, or `nothing` if the result is out of range
function shift(ts::Timestamp{P}, offset::Int64, sign::Int64) where {P}
    ticks, overflow = Base.add_with_overflow(Dates.value(ts), sign * offset * ticks_per_second(P))
    return overflow ? nothing : Timestamp{P}(Dates.UTInstant(P(ticks)))
end

# The UTC offset of `zt` in seconds, or `nothing` if the zone rules are unknown there
function tryoffset(zt::ZonedTimestamp{P,Z}) where {P,Z}
    r = tryrules(Z)
    r === nothing && return nothing
    return ruleoffset(r, fld(Dates.value(zt.utc), ticks_per_second(P)))
end

# The error messages are plain strings: printing a `Timestamp` does not compile under --trim.
norules(Z::Symbol) = ArgumentError(string("time zone \"", String(Z), "\" has no rules for this time"))

# The local time as a `Timestamp{P}`
function localtime(zt::ZonedTimestamp{P,Z}) where {P,Z}
    off = ruleoffset(zonerules(Z), fld(Dates.value(zt.utc), ticks_per_second(P)))
    off === nothing && throw(norules(Z))
    lt = shift(zt.utc, off, Int64(1))
    lt === nothing && throw(OverflowError("the local time is outside the range of Timestamp"))
    return lt
end

### Local time

"""
    Durations.NonExistentTimeError

A local time does not occur in a time zone: clocks skip it when they move forward.
"""
struct NonExistentTimeError <: Exception
    local_time::Timestamp
    zone::Symbol
end

"""
    Durations.AmbiguousTimeError

A local time occurs twice in a time zone because clocks move back. Pass `occurrence=1`
for the earlier time or `occurrence=2` for the later one.
"""
struct AmbiguousTimeError <: Exception
    local_time::Timestamp
    zone::Symbol
end

Base.showerror(io::IO, e::NonExistentTimeError) =
    print(io, "NonExistentTimeError: local time ", e.local_time, " does not exist in time zone ", e.zone)
Base.showerror(io::IO, e::AmbiguousTimeError) =
    print(io, "AmbiguousTimeError: local time ", e.local_time, " is ambiguous in time zone ", e.zone)

"""
    Durations.ZonedTimestamp{P,Z}(ts::Timestamp; occurrence=0)
    Durations.ZonedTimestamp{P,Z}(d::Date, [t::Time]; occurrence=0)
    Durations.ZonedTimestamp{P,Z}(y, [m, d, h, mi, s, ms, us, ns]; occurrence=0)

The time whose local time in zone `Z` is `ts`, or the given date, time, or parts.
"""
function ZonedTimestamp{P,Z}(ts::Timestamp; occurrence::Integer=0) where {P,Z}
    lt = Timestamp{P}(ts)
    r = zonerules(Z)
    tps = ticks_per_second(P)
    candidates = localrules(r, fld(Dates.value(lt), tps))
    n = length(candidates)
    n == 0 && throw(NonExistentTimeError(lt, Z))
    n == 1 || 1 <= occurrence <= n || throw(AmbiguousTimeError(lt, Z))
    utc = shift(lt, r.offsets[candidates[n == 1 ? 1 : occurrence]], Int64(-1))
    utc === nothing && throw(OverflowError("the UTC time is outside the range of Timestamp"))
    inrange(r, fld(Dates.value(utc), tps)) || throw(norules(Z))
    return ZonedTimestamp{P,Z}(utc, UTC)
end

ZonedTimestamp{P,Z}(d::Date, t::Time=Time(0); occurrence::Integer=0) where {P,Z} =
    ZonedTimestamp{P,Z}(Timestamp{P}(d, t); occurrence)
ZonedTimestamp{P,Z}(y::Integer, m::Integer=1, d::Integer=1, h::Integer=0, mi::Integer=0, s::Integer=0,
                    ms::Integer=0, us::Integer=0, ns::Integer=0; occurrence::Integer=0) where {P,Z} =
    ZonedTimestamp{P,Z}(Timestamp{P}(y, m, d, h, mi, s, ms, us, ns); occurrence)

(::Type{Timestamp{P}})(zt::ZonedTimestamp) where {P} = Timestamp{P}(localtime(zt))
(::Type{Timestamp{P}})(zt::ZonedTimestamp, ::Type{UTC}) where {P} = Timestamp{P}(zt.utc)
(::Type{Timestamp})(zt::ZonedTimestamp) = localtime(zt)
(::Type{Timestamp})(zt::ZonedTimestamp, ::Type{UTC}) = zt.utc
Dates.Date(zt::ZonedTimestamp) = Date(localtime(zt))
Dates.Time(zt::ZonedTimestamp) = Time(localtime(zt))
Dates.DateTime(zt::ZonedTimestamp) = DateTime(localtime(zt))

for f in (:days, :hour, :minute, :second, :millisecond, :microsecond, :nanosecond)
    @eval Dates.$f(zt::ZonedTimestamp) = Dates.$f(localtime(zt))
end

for f in (:firstdayofweek, :lastdayofweek, :firstdayofmonth, :lastdayofmonth,
          :firstdayofyear, :lastdayofyear, :firstdayofquarter, :lastdayofquarter)
    @eval Dates.$f(zt::ZonedTimestamp{P,Z}) where {P,Z} = ZonedTimestamp{P,Z}(Dates.$f(Date(zt)))
end

Dates.now(::Type{ZonedTimestamp{P,Z}}) where {P,Z} = ZonedTimestamp{P,Z}(Dates.now(Timestamp{P}, UTC), UTC)

### Comparison and arithmetic: the UTC time for instants, the local time for calendar periods

Dates.value(zt::ZonedTimestamp) = Dates.value(zt.utc)
Base.:(==)(x::ZonedTimestamp, y::ZonedTimestamp) = x.utc == y.utc
Base.:(==)(x::T, y::T) where {T<:ZonedTimestamp} = x.utc == y.utc
Base.isless(x::ZonedTimestamp, y::ZonedTimestamp) = isless(x.utc, y.utc)
Base.isless(x::T, y::T) where {T<:ZonedTimestamp} = isless(x.utc, y.utc)
Base.hash(zt::ZonedTimestamp, h::UInt) = hash(zt.utc, hash(:utc_instant, h))
Base.:(-)(x::ZonedTimestamp, y::ZonedTimestamp) = x.utc - y.utc
Base.:(-)(x::T, y::T) where {T<:ZonedTimestamp} = x.utc - y.utc

Base.promote_rule(::Type{ZonedTimestamp{P,Z}}, ::Type{ZonedTimestamp{Q,Z}}) where {P,Q,Z} =
    ZonedTimestamp{promote_type(P, Q),Z}
Base.convert(::Type{ZonedTimestamp{P,Z}}, zt::ZonedTimestamp{P,Z}) where {P,Z} = zt
Base.convert(::Type{ZonedTimestamp{P,Z}}, zt::ZonedTimestamp{Q,Z}) where {P,Q,Z} = ZonedTimestamp{P,Z}(zt)

for op in (:+, :-)
    @eval begin
        Base.$op(zt::ZonedTimestamp{P,Z}, p::TimePeriod) where {P,Z} = ZonedTimestamp{P,Z}($op(zt.utc, p), UTC)
        Base.$op(zt::ZonedTimestamp{P,Z}, p::DatePeriod) where {P,Z} = ZonedTimestamp{P,Z}($op(localtime(zt), p))
    end
end

Base.floor(zt::ZonedTimestamp{P,Z}, p::DatePeriod) where {P,Z} = ZonedTimestamp{P,Z}(floor(localtime(zt), p))
Base.ceil(zt::ZonedTimestamp{P,Z}, p::DatePeriod) where {P,Z} = ZonedTimestamp{P,Z}(ceil(localtime(zt), p))
# Round the local time at the current offset, so a repeated hour keeps its offset
function Base.floor(zt::ZonedTimestamp{P,Z}, p::TimePeriod) where {P,Z}
    lt = localtime(zt)
    return ZonedTimestamp{P,Z}(floor(lt, p) - (lt - zt.utc), UTC)
end

Dates.guess(a::ZonedTimestamp, b::ZonedTimestamp, c) = Dates.guess(a.utc, b.utc, c)

### Text: the local time and offset, then the zone name in brackets (RFC 9557)

function Base.print(io::IO, zt::ZonedTimestamp{P,Z}) where {P,Z}
    off = tryoffset(zt)
    lt = off === nothing ? nothing : shift(zt.utc, off, Int64(1))
    if lt === nothing
        # "Z" marks a UTC time whose local offset is unknown
        print(io, zt.utc, "Z[", Z, "]")
    else
        print(io, lt, off < 0 ? '-' : '+')
        h, m, s = abs(off) ÷ 3600, abs(off) ÷ 60 % 60, abs(off) % 60
        print(io, h < 10 ? "0" : "", h, m < 10 ? ":0" : ":", m)
        s == 0 || print(io, s < 10 ? ":0" : ":", s)
        print(io, '[', Z, ']')
    end
    return nothing
end

Base.show(io::IO, ::MIME"text/plain", zt::ZonedTimestamp) = print(io, zt)
Base.show(io::IO, zt::ZonedTimestamp) = print(io, typeof(zt), "(\"", zt, "\")")
Base.typeinfo_implicit(::Type{<:ZonedTimestamp}) = true

"""
    Durations.ZonedTimestamp{P,Z}(str::AbstractString)

Parse `str` as printed: a local time, its UTC offset (`"+HH:MM"`, `"-HH:MM"`, or `"Z"` for a
UTC time), and the zone name `Z` in brackets. The offset alone sets the UTC time; it is
not checked against the zone's rules.
"""
function ZonedTimestamp{P,Z}(str::AbstractString) where {P,Z}
    bad() = ArgumentError(string("cannot parse \"", str, "\" as a ZonedTimestamp in time zone \"", Z, "\""))
    zone = string('[', Z, ']')
    endswith(str, zone) || throw(bad())
    body = chop(str; tail=length(zone))
    endswith(body, 'Z') && return ZonedTimestamp{P,Z}(Timestamp{P}(chop(body)), UTC)
    i = findlast(c -> c == '+' || c == '-', body)
    i === nothing && throw(bad())
    parts = split(SubString(body, nextind(body, i)), ':')
    length(parts) in (2, 3) && all(x -> length(x) == 2 && all(isdigit, x), parts) || throw(bad())
    off = sum(parse(Int64, x) * f for (x, f) in zip(parts, (3600, 60, 1)))
    utc = Timestamp{P}(SubString(body, 1, prevind(body, i))) - Second(body[i] == '-' ? -off : off)
    return ZonedTimestamp{P,Z}(utc, UTC)
end

Base.parse(::Type{ZonedTimestamp{P,Z}}, str::AbstractString) where {P,Z} = ZonedTimestamp{P,Z}(str)

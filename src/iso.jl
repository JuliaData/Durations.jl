"""
    Durations.iso2timestamp(Timestamp{P}, text::AbstractString[, RoundDown])::Timestamp{P}
    Durations.iso2timestamp(Timestamp, text::AbstractString[, RoundDown])::Timestamp{Nanosecond}

Parse an ISO 8601 date and time of day with an optional UTC offset, and return
the UTC time. This reads the text that JSON APIs and PostgreSQL write, such as
`"2026-03-08T16:00:00.123Z"`, `"2026-03-08T09:00:00-07:00"`, and
`"2026-03-08 16:00:00.123456+00"`:

- the date, `YYYY-MM-DD`, with a year of 4 to 9 digits and an optional sign;
- `T`, `t`, or a space;
- the time, `hh:mm:ss`, with an optional fraction of 1 to 9 digits after `.`;
- an optional offset: `Z`, `z`, or `±hh`, `±hhmm`, `±hh:mm`, `±hhmmss`, or `±hh:mm:ss`.

Text without an offset is read as UTC. An `ArgumentError` reports anything
else: other text, a date or time field out of range, an offset hour past 23 or
an offset minute or second past 59, a fraction finer than `P` (trailing zeros
are fine), or a UTC time outside the range of `Timestamp{P}`. With `RoundDown`,
fraction digits finer than `P` are dropped instead, flooring the time.

`Timestamp(text)` takes no offset and parses with a `Dates.DateFormat`, which
does not compile under `juliac --trim=safe`. `iso2timestamp` reads the text's
bytes directly and does compile.

```julia
julia> Durations.iso2timestamp(Timestamp{Microsecond}, "2026-03-08 09:00:00.25-07:00")
2026-03-08T16:00:00.25
```
"""
function iso2timestamp end

iso2timestamp(::Type{Timestamp}, text::AbstractString) = iso2timestamp(Timestamp{Dates.Nanosecond}, text)
iso2timestamp(::Type{Timestamp}, text::AbstractString, ::RoundingMode{:Down}) =
    iso2timestamp(Timestamp{Dates.Nanosecond}, text, RoundDown)
iso2timestamp(::Type{Timestamp{P}}, text::AbstractString) where {P} = parseiso(Timestamp{P}, text, false)
iso2timestamp(::Type{Timestamp{P}}, text::AbstractString, ::RoundingMode{:Down}) where {P} =
    parseiso(Timestamp{P}, text, true)

@inline isodigit(b::UInt8) = UInt8('0') <= b <= UInt8('9')

# Whether the byte at `k` exists and is `c`.
@inline isobyte(b, k::Int, c::Char) = k <= length(b) && b[k] == UInt8(c)

# The value of the `width` digits that start at `i`, or -1 if they run past the
# end or one is not a digit.
@inline function isodigits(b, i::Int, width::Int)
    i + width - 1 <= length(b) || return Int64(-1)
    value = Int64(0)
    for k in i:(i + width - 1)
        isodigit(b[k]) || return Int64(-1)
        value = 10 * value + Int64(b[k] - UInt8('0'))
    end
    return value
end

# The messages are plain strings: printing a `Timestamp` does not compile under --trim.
@noinline isoerror(text::AbstractString, why::String) =
    throw(ArgumentError(string("cannot parse \"", text, "\" as an ISO 8601 timestamp: ", why)))

function parseiso(::Type{Timestamp{P}}, text::AbstractString, round_down::Bool) where {P}
    b = codeunits(text)
    n = length(b)
    i = 1
    negative = isobyte(b, 1, '-')
    (negative || isobyte(b, 1, '+')) && (i = 2)
    year_start = i
    year = Int64(0)
    while i <= n && isodigit(b[i])
        i - year_start < 9 && (year = 10 * year + Int64(b[i] - UInt8('0')))
        i += 1
    end
    4 <= i - year_start <= 9 || isoerror(text, "expected a year of 4 to 9 digits")
    negative && (year = -year)
    month = isobyte(b, i, '-') ? isodigits(b, i + 1, 2) : Int64(-1)
    day = month >= 0 && isobyte(b, i + 3, '-') ? isodigits(b, i + 4, 2) : Int64(-1)
    day >= 0 || isoerror(text, "expected the date as YYYY-MM-DD")
    i += 6
    isobyte(b, i, 'T') || isobyte(b, i, 't') || isobyte(b, i, ' ') ||
        isoerror(text, "expected T or a space after the date")
    hour = isodigits(b, i + 1, 2)
    minute = hour >= 0 && isobyte(b, i + 3, ':') ? isodigits(b, i + 4, 2) : Int64(-1)
    second = minute >= 0 && isobyte(b, i + 6, ':') ? isodigits(b, i + 7, 2) : Int64(-1)
    second >= 0 || isoerror(text, "expected the time as hh:mm:ss")
    i += 9
    fraction = Int64(0)  # nanoseconds
    if isobyte(b, i, '.')
        i += 1
        digits_start = i
        scale = Int64(100_000_000)
        while i <= n && isodigit(b[i])
            i - digits_start < 9 || isoerror(text, "a fraction can have at most 9 digits")
            fraction += Int64(b[i] - UInt8('0')) * scale
            scale ÷= 10
            i += 1
        end
        i > digits_start || isoerror(text, "expected digits after the decimal point")
    end
    offset = Int64(0)  # seconds east of UTC
    if isobyte(b, i, 'Z') || isobyte(b, i, 'z')
        i += 1
    elseif isobyte(b, i, '+') || isobyte(b, i, '-')
        sign = isobyte(b, i, '-') ? Int64(-1) : Int64(1)
        offset_hours = isodigits(b, i + 1, 2)
        offset_hours >= 0 || isoerror(text, "expected a two-digit offset hour")
        i += 3
        offset_minutes = Int64(0)
        offset_seconds = Int64(0)
        if i <= n
            separator = isobyte(b, i, ':') ? 1 : 0
            offset_minutes = isodigits(b, i + separator, 2)
            offset_minutes >= 0 || isoerror(text, "expected a two-digit offset minute")
            i += separator + 2
            if i <= n
                isobyte(b, i, ':') == (separator == 1) ||
                    isoerror(text, "expected the offset's seconds after the same separator")
                offset_seconds = isodigits(b, i + separator, 2)
                offset_seconds >= 0 || isoerror(text, "expected two-digit offset seconds")
                i += separator + 2
            end
        end
        offset_hours <= 23 && offset_minutes <= 59 && offset_seconds <= 59 ||
            isoerror(text, "the offset is out of range")
        offset = sign * (3600 * offset_hours + 60 * offset_minutes + offset_seconds)
    end
    i == n + 1 || isoerror(text, "unexpected text after the time")
    if round_down
        per_second = ticks_per_second(P)
        per_second < 1_000_000_000 && (fraction -= fraction % (1_000_000_000 ÷ per_second))
    end
    milliseconds, rest = divrem(fraction, 1_000_000)
    microseconds, nanoseconds = divrem(rest, 1_000)
    clock = Timestamp{P}(year, month, day, hour, minute, second, milliseconds, microseconds, nanoseconds)
    offset == 0 && return clock
    utc = shift(clock, offset, Int64(-1))
    utc === nothing && isoerror(text, "the UTC time is out of range")
    return utc
end

# Load explicitly with include("examples/subnanosecond.jl").
# These experimental types are not part of Durations' exported API.
module Subnanosecond

using Dates, Durations
using Dates: value

const TimestampHelpers = Durations.TIMESTAMP_FROM_DATES ? Dates : Durations

abstract type SubnanosecondPeriod <: Dates.TimePeriod end

for (name, digits) in ((:Picosecond, 12), (:Femtosecond, 15), (:Attosecond, 18))
    @eval begin
        primitive type $name <: SubnanosecondPeriod 128 end
        $name(x::Real) = reinterpret($name, Int128(x))
        Dates.value(x::$name) = reinterpret(Int128, x)
        Base.typemin(::Type{$name}) = $name(typemin(Int128))
        Base.typemax(::Type{$name}) = $name(typemax(Int128))
        precision(::Type{$name}) = $digits
    end
end

# ponytail: BigInt rational intermediates keep this example exact at Int128
# endpoints; use checked integer scale ratios if profiling justifies it.
TimestampHelpers.timestamp_scale(::Type{P}) where {P<:SubnanosecondPeriod} =
    1 // big(10)^(precision(P) - 9)
TimestampHelpers.timestamp_totaldays(::Type{P}, y, m, d) where {P<:SubnanosecondPeriod} =
    Dates.totaldays(big(y), m, d)
Dates.tons(x::P) where {P<:SubnanosecondPeriod} = value(x) * TimestampHelpers.timestamp_scale(P)
Dates._units(x::P) where {P<:SubnanosecondPeriod} =
    " " * lowercase(string(nameof(P))) * (value(x) in (-1, 1) ? "" : "s")

# Extend fractional display without narrowing to the Dates Nanosecond type.
function Dates.format(io, d::Dates.DatePart{'n'}, x::Timestamp{P}) where {P<:SubnanosecondPeriod}
    fraction = mod(value(x), big(10)^precision(P))
    TimestampHelpers.format_fraction(io, d, fraction, precision(P))
end

# Parsing fractional strings beyond nine digits is outside this example.
# repr instead emits an exact, executable raw-count constructor.
function Base.show(io::IO, x::Timestamp{P}) where {P<:SubnanosecondPeriod}
    print(io, "convert(", typeof(x), ", ", P, "(", value(x), "))")
end

end

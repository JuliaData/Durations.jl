# Arrow.jl integration: a `Timestamp{P}` column is Arrow's own timestamp logical type at
# the matching unit (no time zone), and a `ZonedTimestamp{P,Z}` column is that type with
# time zone `String(Z)`. Each is tagged with an extension name so that it reads back as the
# same Julia type. A reader without Durations loaded sees a plain Arrow timestamp column.
module DurationsArrowExt

using Durations: Timestamp, ZonedTimestamp
using Dates: Dates, Second, Millisecond, Microsecond, Nanosecond, UTC
using Arrow: Arrow
const ArrowTypes = Arrow.ArrowTypes
const Meta = Arrow.Meta

arrowunit(::Type{Second}) = Meta.TimeUnit.SECOND
arrowunit(::Type{Millisecond}) = Meta.TimeUnit.MILLISECOND
arrowunit(::Type{Microsecond}) = Meta.TimeUnit.MICROSECOND
arrowunit(::Type{Nanosecond}) = Meta.TimeUnit.NANOSECOND

function juliaunit(u::Meta.TimeUnit.T)
    u == Meta.TimeUnit.SECOND && return Second
    u == Meta.TimeUnit.MILLISECOND && return Millisecond
    u == Meta.TimeUnit.MICROSECOND && return Microsecond
    return Nanosecond
end

const TIMESTAMP_SYMBOL = Symbol("JuliaLang.Durations.Timestamp")

ArrowTypes.ArrowKind(::Type{<:Timestamp}) = ArrowTypes.PrimitiveKind()
ArrowTypes.ArrowType(::Type{Timestamp{P}}) where {P} = Arrow.Timestamp{arrowunit(P),nothing}
ArrowTypes.toarrow(x::Timestamp{P}) where {P} = Arrow.Timestamp{arrowunit(P),nothing}(Dates.value(x))
ArrowTypes.arrowname(::Type{<:Timestamp}) = TIMESTAMP_SYMBOL
ArrowTypes.JuliaType(::Val{TIMESTAMP_SYMBOL}, ::Type{Arrow.Timestamp{U,nothing}}) where {U} = Timestamp{juliaunit(U)}
# the file's unit normally equals `P` (JuliaType chose it); a different `P` converts exactly or throws
ArrowTypes.fromarrow(::Type{Timestamp{P}}, x::Arrow.Timestamp{U,nothing}) where {P,U} =
    Timestamp{P}(Timestamp{juliaunit(U)}(Dates.UTInstant(juliaunit(U)(x.x))))
ArrowTypes.default(::Type{Timestamp{P}}) where {P} = Timestamp{P}(Dates.UTInstant(P(0)))

const ZONED_SYMBOL = Symbol("JuliaLang.Durations.ZonedTimestamp")

ArrowTypes.ArrowKind(::Type{<:ZonedTimestamp}) = ArrowTypes.PrimitiveKind()
ArrowTypes.ArrowType(::Type{ZonedTimestamp{P,Z}}) where {P,Z} = Arrow.Timestamp{arrowunit(P),Z}
ArrowTypes.toarrow(x::ZonedTimestamp{P,Z}) where {P,Z} = Arrow.Timestamp{arrowunit(P),Z}(Dates.value(x.utc))
ArrowTypes.arrowname(::Type{<:ZonedTimestamp}) = ZONED_SYMBOL
ArrowTypes.JuliaType(::Val{ZONED_SYMBOL}, ::Type{Arrow.Timestamp{U,Z}}) where {U,Z} =
    ZonedTimestamp{juliaunit(U),Z}
ArrowTypes.fromarrow(::Type{ZonedTimestamp{P,Z}}, x::Arrow.Timestamp{U}) where {P,Z,U} =
    ZonedTimestamp{P,Z}(Timestamp{juliaunit(U)}(Dates.UTInstant(juliaunit(U)(x.x))), UTC)
ArrowTypes.default(::Type{ZonedTimestamp{P,Z}}) where {P,Z} =
    ZonedTimestamp{P,Z}(Timestamp{P}(Dates.UTInstant(P(0))), UTC)

end

# Arrow.jl integration: a `Timestamp{P}` column is Arrow's own timestamp logical type at
# the matching unit (no time zone), tagged with an extension name so that it reads back as
# `Timestamp{P}`. A reader without Durations loaded sees a plain Arrow timestamp column.
module DurationsArrowExt

using Durations: Timestamp
using Dates: Dates, Second, Millisecond, Microsecond, Nanosecond
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

end

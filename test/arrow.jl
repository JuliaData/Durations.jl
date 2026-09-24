using Arrow
const DurationsArrowExt = Base.get_extension(Durations, :DurationsArrowExt)

@testset "Arrow" begin
    for P in (Second, Millisecond, Microsecond, Nanosecond)
        col = [Timestamp{P}(Dates.UTInstant(P(123_456_789))), Timestamp{P}(Dates.UTInstant(P(-1))), Timestamp{P}(1970)]
        t = Arrow.Table(Arrow.tobuffer((ts=col, mts=[col[1], missing, col[3]])))
        @test eltype(t.ts) === Timestamp{P}
        @test collect(t.ts) == col
        @test eltype(t.mts) === Union{Missing,Timestamp{P}}
        @test isequal(collect(t.mts), [col[1], missing, col[3]])
        # the column is Arrow's own timestamp type at the matching unit
        raw = Arrow.Table(Arrow.tobuffer((ts=col,)); convert=false)
        @test eltype(raw.ts) === Arrow.Timestamp{DurationsArrowExt.arrowunit(P),nothing}
        @test [x.x for x in raw.ts] == Dates.value.(col)
    end
    for P in (Second, Millisecond, Microsecond, Nanosecond),
        Z in (:UTC, Symbol("+07:30"), Symbol("America/Denver"), Symbol("Vendor/Unknown"))
        T = Durations.ZonedTimestamp{P,Z}
        col = reinterpret(T, Int64[123_456_789, -1, 0, typemin(Int64), typemax(Int64)])
        mcol = [col[1], missing, col[3], missing, col[5]]
        t = Arrow.Table(Arrow.tobuffer((zt=col, mzt=mcol)))
        @test eltype(t.zt) === T
        @test reinterpret(Int64, collect(t.zt)) == Dates.value.(col)
        @test eltype(t.mzt) === Union{Missing,T}
        @test isequal(collect(t.mzt), mcol)
        # the column is Arrow's own timestamp type with the zone name as its time zone
        raw = Arrow.Table(Arrow.tobuffer((zt=col,)); convert=false)
        @test eltype(raw.zt) === Arrow.Timestamp{DurationsArrowExt.arrowunit(P),Z}
        @test [x.x for x in raw.zt] == Dates.value.(col)
    end
    # Arrow.jl's own mapping of DateTime is untouched
    t = Arrow.Table(Arrow.tobuffer((dt=[DateTime(2026, 1, 1)],)))
    @test eltype(t.dt) === DateTime
end

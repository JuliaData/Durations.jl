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
    # Arrow.jl's own mapping of DateTime is untouched
    t = Arrow.Table(Arrow.tobuffer((dt=[DateTime(2026, 1, 1)],)))
    @test eltype(t.dt) === DateTime
end

# The Arrow 3.x facade owns native value mappings. Exercise the wire contract
# through its core IPC reader and writer without depending on facade defaults.
const AC = Arrow.ArrowCore
@testset "Arrow 3 timestamp primitive storage" begin
    @test Base.get_extension(Durations, :DurationsArrowExt) !== nothing
    @test !isdefined(Arrow, :Timestamp)
    for (P, unit) in ((Second, AC.SECOND), (Millisecond, AC.MILLISECOND), (Microsecond, AC.MICROSECOND), (Nanosecond, AC.NANOSECOND)),
        zone in (nothing, "", "UTC", "+07:30", "America/Denver", "Vendor/Unknown"),
        nullable in (false, true), file in (false, true)
        T = zone === nothing || isempty(zone) ? Timestamp{P} : Durations.ZonedTimestamp{P,Symbol(zone)}
        counts = Int64[typemin(Int64), -1, 0, 1, typemax(Int64)]
        values = collect(reinterpret(T, counts))
        type = AC.TimestampType(unit, zone)
        validity = nullable ? AC._databuffer(UInt8[0x1b]) : AC.BufferSlice()
        data = AC.ArrayData(type, length(values), [validity, AC._databuffer(values)]; nullcount=nullable ? 1 : 0)
        field = AC.Field("ts", type; nullable)
        schema = AC.Schema([field])
        batch = AC.RecordBatch(schema, [data])
        bytes = file ? Arrow.writefile(schema, [batch]) : Arrow.writestream(schema, [batch])
        decoded = file ? Arrow.readfile(bytes) : Arrow.readstream(bytes)
        f = decoded.schema.fields[1]
        d = (file ? decoded[1] : decoded.batches[1]).columns[1]
        @test f.type.unit == unit
        @test f.type.timezone == zone
        raw = AC.materialize(f, d)
        expected = nullable ? Union{Missing,Int64}[counts[1],counts[2],missing,counts[4],counts[5]] : counts
        @test isequal(raw, expected)
        @test reinterpret(Int64, values) == counts
        @test sizeof(T) == 8 && isbitstype(T)
    end
end

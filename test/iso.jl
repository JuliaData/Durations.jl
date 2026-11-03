using Durations: iso2timestamp

@testset "iso2timestamp" begin
    U = Timestamp{Microsecond}
    noon = U(2026, 3, 8, 16)

    @testset "Accepted forms" begin
        for text in ("2026-03-08T16:00:00Z", "2026-03-08t16:00:00z", "2026-03-08 16:00:00Z",
                     "2026-03-08T16:00:00", "2026-03-08T16:00:00+00", "2026-03-08T16:00:00-00:00",
                     "2026-03-08T09:00:00-07", "2026-03-08T09:00:00-0700", "2026-03-08T09:00:00-07:00",
                     "2026-03-08T21:30:00+05:30", "2026-03-08T21:30:00+0530", "2026-03-08T16:00:00.000Z",
                     "+2026-03-08T16:00:00Z")
            @test iso2timestamp(U, text) === noon
        end
        # fractions of 1 to 9 digits; digits finer than the resolution may be zeros
        @test iso2timestamp(U, "2026-03-08T16:00:00.5Z") == noon + Millisecond(500)
        @test iso2timestamp(U, "2026-03-08T16:00:00.123456Z") == noon + Microsecond(123456)
        @test iso2timestamp(U, "2026-03-08T16:00:00.123456000Z") == noon + Microsecond(123456)
        @test iso2timestamp(Timestamp{Nanosecond}, "2026-03-08T16:00:00.123456789Z") ==
              Timestamp(2026, 3, 8, 16, 0, 0, 123, 456, 789)
        # PostgreSQL text: a space, six digits, an hour offset, and LMT-era offset seconds
        @test iso2timestamp(U, "2026-03-08 09:00:00.25-07") == noon + Millisecond(250)
        @test iso2timestamp(U, "1900-01-01 00:00:00+05:53:28") == U(1899, 12, 31, 18, 6, 32)
        @test iso2timestamp(U, "1900-01-01 00:00:00+055328") == U(1899, 12, 31, 18, 6, 32)
        # years wider than four digits, and signed years where the resolution reaches them
        @test iso2timestamp(U, "10000-01-01T00:00:00Z") == U(10000)
        @test iso2timestamp(Timestamp{Second}, "-0001-12-31T23:59:59Z") == Timestamp{Second}(-1, 12, 31, 23, 59, 59)
        # the time fields follow the by-parts constructor, which takes 24:00:00 as the next midnight
        @test iso2timestamp(U, "2026-03-08T24:00:00Z") == U(2026, 3, 9)
        # every resolution, and `Timestamp` meaning nanoseconds
        for P in (Second, Millisecond, Microsecond, Nanosecond)
            @test iso2timestamp(Timestamp{P}, "2026-03-08T09:00:00-07:00") === Timestamp{P}(2026, 3, 8, 16)
        end
        @test iso2timestamp(Timestamp, "2026-03-08T16:00:00Z") isa Timestamp{Nanosecond}
        # text without an offset reads as `Timestamp(text)` does
        @test iso2timestamp(Timestamp{Nanosecond}, "2026-08-31T13:45:30.123456789") ==
              Timestamp("2026-08-31T13:45:30.123456789")
        # any string type
        @test iso2timestamp(U, SubString("x2026-03-08T16:00:00Zx", 2, 21)) === noon
        @test iso2timestamp(U, Test.GenericString("2026-03-08T16:00:00Z")) === noon
    end

    @testset "Rejected text" begin
        for text in ("", "2026", "2026-03", "2026-03-08", "2026-03-08T16:00", "2026-03-08T16:00:0",
                     "026-03-08T16:00:00Z", "1234567890-01-01T00:00:00Z", "2026/03/08T16:00:00Z",
                     "2026-03-08_16:00:00Z", "2026-3-08T16:00:00Z", "2026-03-08T16:00:00.",
                     "2026-03-08T16:00:00.1234567890Z", "2026-03-08T16:00:00Zx", "2026-03-08T16:00:00 Z",
                     " 2026-03-08T16:00:00Z", "2026-03-08T16:00:00+7", "2026-03-08T16:00:00+07:", "2026-03-08T16:00:00+07:0",
                     "2026-03-08T16:00:00+07:0030", "2026-03-08T16:00:00+0700:30", "2026-03-08T16:00:00+24:00",
                     "2026-03-08T16:00:00+01:60", "2026-03-08T16:00:00+01:00:60",
                     "2026-02-30T00:00:00Z", "2026-13-01T00:00:00Z", "2026-03-08T25:00:00Z",
                     "2026-03-08T16:60:00Z", "2026-03-08T16:00:60Z", "2026-03-08T16:00:00.1234567Z")
            @test_throws ArgumentError iso2timestamp(U, text)
        end
        e = try iso2timestamp(U, "2026-03-08T16:00:00+24:00") catch e e end
        @test e.msg == "cannot parse \"2026-03-08T16:00:00+24:00\" as an ISO 8601 timestamp: the offset is out of range"
        # the UTC time must fit the resolution, not only the local time
        @test iso2timestamp(Timestamp, "2262-04-11T22:47:16.854775807-01:00") == typemax(Timestamp{Nanosecond})
        @test_throws ArgumentError iso2timestamp(Timestamp, "2262-04-11T23:47:16.854775807-01:00")
        @test_throws ArgumentError iso2timestamp(Timestamp, "1677-09-21T00:12:43.145224192+01:00")
    end

    @testset "RoundDown" begin
        # digits finer than the resolution floor the time instead of throwing
        @test iso2timestamp(Timestamp{Millisecond}, "1969-12-31 23:59:59.999999", RoundDown) ==
              Timestamp{Millisecond}(1969, 12, 31, 23, 59, 59, 999)
        @test iso2timestamp(Timestamp{Second}, "2026-03-08T16:00:00.999Z", RoundDown) == Timestamp{Second}(2026, 3, 8, 16)
        @test iso2timestamp(Timestamp{Millisecond}, "294276-12-31 23:59:59.999999+00", RoundDown) ==
              Timestamp{Millisecond}(294276, 12, 31, 23, 59, 59, 999)
        @test iso2timestamp(Timestamp, "2026-03-08T16:00:00.123456789Z", RoundDown) ===
              Timestamp(2026, 3, 8, 16, 0, 0, 123, 456, 789)
        @test iso2timestamp(U, "2026-03-08T09:00:00.0000009-07:00", RoundDown) === noon
        # flooring changes nothing else: bad text and ranges still throw
        @test_throws ArgumentError iso2timestamp(U, "2026-03-08T16:00:00+24:00", RoundDown)
        @test_throws ArgumentError iso2timestamp(Timestamp, "2262-04-11T23:47:16.854775807-01:00", RoundDown)
        @test_throws MethodError iso2timestamp(U, "2026-03-08T16:00:00.5Z", RoundUp)
    end

    @testset "Round trips" begin
        for ts in (noon, noon + Microsecond(1), U(1), U(10000, 12, 31, 23, 59, 59, 999, 999))
            @test iso2timestamp(U, string(ts, "Z")) === ts
        end
        J = Durations.ZonedTimestamp{Microsecond,Symbol("+07:00")}
        zt = J(U(2026, 3, 8, 23, 0, 0, 0, 1))
        text = string(Timestamp(zt), "+07:00")
        @test iso2timestamp(U, text) == Timestamp(zt, UTC)
    end
end

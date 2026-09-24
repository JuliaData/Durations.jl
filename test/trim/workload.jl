using Durations, Dates

function (@main)(args::Vector{String})::Cint
    x = Duration(2,-3,456)
    y = Duration(Month(1))
    x + y == Duration(3,-3,456) || return 1
    2*x == Duration(4,-6,912) || return 2
    iszero(x-x) || return 3
    sizeof(Duration) == 16 || return 4
    hash(x) == hash(Duration(2,-3,456)) || return 5
    v = [x,y]
    sum(v) == x+y || return 6
    ts = Timestamp(2026, 8, 31, 13, 45, 30, 123, 456, 789)
    sizeof(ts) == 8 || return 7
    Dates.value(ts + Nanosecond(1)) == Dates.value(ts) + 1 || return 8
    ts - Timestamp(2026, 8, 31) == Nanosecond(49530123456789) || return 9
    (year(ts), month(ts), day(ts), hour(ts), nanosecond(ts)) == (2026, 8, 31, 13, 789) || return 10
    floor(ts, Minute(15)) == Timestamp(2026, 8, 31, 13, 45) || return 11
    Timestamp{Microsecond}(floor(ts, Microsecond)) < ts || return 12
    DateTime(ts) == DateTime(2026, 8, 31, 13, 45, 30, 123) || return 13
    hash(ts) == hash(Timestamp(2026, 8, 31, 13, 45, 30, 123, 456, 789)) || return 14
    # the constructor's error paths: their messages must compile under --trim=safe (the
    # parts are not constants, so the calls are not folded into unconditional throws)
    n = length(args)
    try
        Timestamp(2026, 2, 30 + n)
        return 15
    catch e
        e isa ArgumentError || return 16
        (e.msg::String) == "Day: 30 out of range (1:28)" || return 17
    end
    try
        Timestamp{Nanosecond}(1677, 9, 21 + n)
        return 18
    catch e
        e isa ArgumentError || return 19
        (e.msg::String) == "Timestamp: 1677-9-21 out of range for Timestamp{Nanosecond} (1677-9-21 to 2262-4-11)" || return 20
    end
    try
        Timestamp{Second}(2026, 1, 1, 0, 0, 0, 500 + n)
        return 21
    catch e
        e isa ArgumentError || return 22
        (e.msg::String) == "Fractional second is not exactly representable as Timestamp{Second}" || return 23
    end
    # ZonedTimestamp with the zone rules Durations knows ("UTC" and fixed offsets)
    J = Durations.ZonedTimestamp{Nanosecond,Symbol("+07:00")}
    zt = J(Timestamp(2026, 3, 8, 16, 0, 0, 0, 0, 5))
    Dates.value(zt.utc) == Dates.value(Timestamp(2026, 3, 8, 9, 0, 0, 0, 0, 5)) || return 30
    hour(zt) == 16 || return 31
    Timestamp(zt + Day(1)) == Timestamp(2026, 3, 9, 16, 0, 0, 0, 0, 5) || return 32
    U = Durations.ZonedTimestamp{Nanosecond,:UTC}
    U(zt) == zt || return 33
    hash(U(zt)) == hash(zt) || return 34
    Timestamp(floor(zt, Day)) == Timestamp(2026, 3, 8) || return 35
    v = reinterpret(J, Int64[0, 1])
    v[2] - v[1] == Nanosecond(1) || return 36
    Core.println("trim workload passed")
    return 0
end

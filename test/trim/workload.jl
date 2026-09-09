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
    Core.println("trim workload passed")
    return 0
end

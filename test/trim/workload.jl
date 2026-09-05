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
    Core.println("trim workload passed")
    return 0
end

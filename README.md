# Durations.jl

A fixed-width calendar interval for Julia data tools. `Duration` stores months,
days, and nanoseconds as independent signed fields. It matches Arrow's
[MONTH_DAY_NANO interval](https://github.com/apache/arrow/blob/main/format/Schema.fbs)
layout: Int32 months, Int32 days, Int64 nanoseconds, with no padding.

This represents a calendar interval. Arrow's separately named Duration type is
an eight-byte elapsed-time count; this package's three-field value is different.

```julia
using Durations, Dates

x = Duration(months=2, days=-3, nanoseconds=1_000)
@assert sizeof(x) == 16
@assert x.months == 2
@assert x + Duration(Month(1)) == Duration(3, -3, 1_000)
@assert 2*x == Duration(4, -6, 2_000)
@assert Duration(Dates.CompoundPeriod(x)) == x
@assert Duration(Month(2) + Day(3)) == Duration(2, 3, 0)
```

After registration, install with `import Pkg; Pkg.add("Durations")`.
Julia 1.10 and later are supported. Dates is the only runtime dependency.

## Contract

- `Duration(months, days, nanoseconds)` checks conversion to Int32/Int32/Int64.
  The keyword constructor defaults each field to zero.
- Fields are independent. Signs may differ. Nanoseconds may exceed one day's
  worth. There is no automatic normalization between months, days, or nanoseconds.
- `+`, `-`, unary negation, and multiplication by integers check overflow.
  Multiplication uses an Int128 intermediate; a nonzero component rejects an
  integer multiplier that cannot fit that intermediate.
- Equality and hashing compare the three components. A month does not equal
  30 days. A day does not equal 86,400 seconds. Calendar context can change their
  elapsed lengths. Sorting and division are intentionally undefined.
- `zero`, `iszero`, `sum`, broadcasting, and typed `repr` work as expected.
- Construct from Dates periods or CompoundPeriod. Years and quarters become
  months; weeks become days; hours through nanoseconds become nanoseconds.
  Conversion is exact or throws when a component exceeds its storage range.
- Convert explicitly to `Dates.CompoundPeriod` for calendar operations. Check
  the destination clock resolution: DateTime stores milliseconds, so it cannot
  retain arbitrary nanoseconds. No automatic Date/DateTime arithmetic is added.

## Wire interoperability

Field offsets are 0, 4, and 8 bytes. A `Vector{Duration}` is a contiguous
coefficient buffer. Raw bytes use host endianness. Arrow adapters must honor the
schema byte order and carry nulls in their validity bitmap. Null is `missing`,
not a sentinel Duration.

Parquet/Avro month-day-millisecond fields and database microsecond fields can
scale their sub-day count into nanoseconds using checked arithmetic. The source
unit's full range may exceed Int64 nanoseconds. Reverse conversion must also
check divisibility. No lossy conversion is provided by this package.

## Testing

```sh
julia --project -e 'using Pkg; Pkg.test()'
julia --project=test/trim -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=test/trim test/trim/runtests.jl
```

CI covers Julia 1.10, 1.11, current stable, and nightly on Linux, Windows, and
macOS. Trim CI compiles and executes a JuliaC `--trim=safe` workload. Tests check
layout, byte round trips, overflow, mixed signs, Dates conversions, and hashing,
and run the Dates stdlib's `Timestamp` test file against whichever
implementation is active.

## Timestamp

`Timestamp{P}` is a point in time stored as an `Int64` count since the Unix
epoch `1970-01-01T00:00:00`, with `P` one of `Second`, `Millisecond`,
`Microsecond`, or `Nanosecond`. It is the type proposed for the Julia 1.14
Dates stdlib in [JuliaLang/julia#62994](https://github.com/JuliaLang/julia/pull/62994).
Durations makes it available to packages on earlier Julia versions:

- When the Dates stdlib defines `Timestamp`, `Durations.Timestamp` is
  `Dates.Timestamp` itself, and `Durations.unix2timestamp`,
  `Durations.timestamp2unix`, and `Durations.ISOTimestampFormat` are the Dates
  bindings.
- Otherwise Durations supplies a compatible implementation with the same
  constructors, accessors, conversions, promotion, comparison, arithmetic,
  rounding, adjusters, ranges, parsing, and formatting.
  `Durations.TIMESTAMP_FROM_DATES` reports which case applies.

```julia
using Durations, Dates

ts = Timestamp(2026, 8, 31, 13, 45, 30, 123, 456, 789)   # Timestamp{Nanosecond}
@assert string(ts) == "2026-08-31T13:45:30.123456789"
@assert Timestamp(string(ts)) == ts
@assert Timestamp{Microsecond}("2026-08-31T13:45:30.123456") < ts
@assert ts - DateTime(2026, 8, 31, 13, 45, 30, 123) == Nanosecond(456789)
@assert floor(ts, Minute(15)) == Timestamp(2026, 8, 31, 13, 45)
@assert reinterpret(Int64, [Timestamp(1970)]) == [0]      # Arrow timestamp[ns] layout
@assert Timestamp{Second}(Dates.UTInstant(Second(86400))) == Date(1970, 1, 2)
```

Plain `Timestamp(...)` means `Timestamp{Nanosecond}`, which covers 1677 through
2262. Coarser resolutions cover wider ranges. Conversions between resolutions,
period arithmetic, and rounding require exact representation and throw an
`InexactError` otherwise; `+` and `-` wrap at the ends of the `Int64` range like
`DateTime`. Use a concrete `Timestamp{P}` for array element types and struct
fields.

Differences on Julia versions that use the compatibility implementation:

- Loading Durations registers the `n` fractional-second format code with
  Dates. A `DateFormat` that used a literal `n` as a separator must escape it as
  `\n`. `n` parses and formats `Timestamp`, and formats `DateTime` and `Time`.
  Parsing a `DateTime` or `Time` with `n` is unreliable before Julia 1.14: a
  `DateTime` format drops the fraction and a `Time` rejects sub-millisecond
  digits. Parse a `Timestamp` and convert instead.
- `hash` agrees with `==` between `Timestamp` and `DateTime`, and across
  `Timestamp` resolutions. Equal `Date` and `Timestamp` values hash differently,
  as equal `Date` and `DateTime` values already do on these versions.
- `now(Timestamp)` reads the system clock through `clock_gettime` on POSIX and
  `GetSystemTimePreciseAsFileTime` on Windows.
- `Dates.isoyear` and `Dates.isoweekdate` accept a `Timestamp` only where Dates
  defines them (Julia 1.13 and later).
- Parsing a negative year, which only `Timestamp{Second}`, `Timestamp{Millisecond}`,
  and `Timestamp{Microsecond}` can represent, requires the Julia 1.12 Dates parser.

## Arrow interoperability

With Arrow.jl loaded, a `Timestamp{P}` column is written as Arrow's own timestamp type
at unit `P` (seconds, milliseconds, microseconds, or nanoseconds; no time zone), tagged
with the extension name `JuliaLang.Durations.Timestamp` so that it reads back as
`Timestamp{P}`. A reader without Durations loaded sees a plain Arrow timestamp column.

## Package-defined Timestamp periods

Packages can extend `Timestamp{P}` with a `Dates.TimePeriod` that stores its own
count, including a primitive Int128 period. The internal helpers obtain the count
through `Dates.value`, its bounds through `typemin`/`typemax`, and its exact scale
in nanoseconds through `timestamp_scale(P)`. A rational scale supports units finer
than a nanosecond. Wider calendar calculations can specialize
`timestamp_totaldays(P, y, m, d)`. Fractional formatting and parsing are separate
extensions. Add custom periods with `+` or use `convert(Timestamp{P}, P(count))`
for raw epoch counts; unsupported calendar parts throw instead of being ignored.

These helpers are internal and may change with the Dates proposal. The four
built-in resolutions keep their existing representation and behavior. The
[sub-nanosecond prototype](https://github.com/JuliaData/Durations.jl/pull/4)
demonstrates package-defined picoseconds, femtoseconds, and attoseconds.

## Sub-nanosecond prototype

This branch demonstrates package-defined resolutions for `Timestamp{P}`.
Load [the example](examples/subnanosecond.jl) explicitly; it adds no exports
or runtime dependencies to Durations.

```julia
using Dates, Durations
include("examples/subnanosecond.jl")
using .Subnanosecond: Picosecond, Femtosecond, Attosecond

t = Timestamp{Picosecond}(2026, 9, 24)
x = t + Picosecond(1)
@assert string(x) == "2026-09-24T00:00:00.000000000001"
@assert x - t == Picosecond(1)
@assert floor(x, Nanosecond) == t
@assert ceil(x, Nanosecond) == t + Nanosecond(1)
@assert x + Month(1) == Timestamp{Picosecond}(2026, 10, 24) + Picosecond(1)

f = Timestamp{Femtosecond}(x) + Femtosecond(1)
@assert f - x == Femtosecond(1)
@assert Timestamp{Attosecond}(f) == f
@assert sizeof(x) == 16
@assert Dates.value(x) isa Int128
@assert collect(t:Picosecond(1):t+Picosecond(2)) == [t, x, t+Picosecond(2)]
```

Each period is a 128-bit primitive type containing an Int128 count.
`Timestamp{P}` still contains only `UTInstant{P}`. The example supplies the
period's value, limits, scale in nanoseconds, and fractional display. Existing
timestamp code supplies construction, exact conversions, comparison, hashing,
arithmetic, rounding, and ranges. Converting `x` above to
`Timestamp{Nanosecond}` throws `InexactError`; round first to discard precision.
Add custom periods with `+`, or use `convert(Timestamp{P}, P(count))` for raw
epoch counts. The calendar-parts constructor rejects unsupported period parts.

The shared changes admit custom TimePeriod types, read counts through
`Dates.value`, obtain count limits from the period, and accept fractional scales.
The four built-in resolutions retain Int64 storage and their existing behavior.
The example uses BigInt rational intermediates to keep endpoint calculations
exact and the implementation short. This is a design demonstration, not a
performance claim or a stable extension API.

The example works with either Durations' compatibility Timestamp or the Dates
Timestamp with the shared extension helpers. It formats 12/15/18 fractional digits;
parsing beyond nine digits is not implemented. `repr` uses an exact raw-count
constructor. Date/DateTime/Time conversions retain their destination range and
precision limits. Arrow's native timestamp units stop at nanoseconds; this
prototype does not add a sub-nanosecond wire format.

Run the example checks with `julia --project test/subnanosecond.jl`, or run the
complete package suite normally. No release or version bump is proposed.

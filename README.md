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
layout, byte round trips, overflow, mixed signs, Dates conversions, and hashing.

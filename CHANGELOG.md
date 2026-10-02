# Changelog

## 1.4.1

Bring the `Timestamp{P}` compatibility implementation in line with the merged
Julia 1.14 Dates implementation. Keep fractional-resolution arithmetic,
calendar fields, and local clocks exact; avoid intermediate overflow in wide
conversions, rounding, and ranges; and align resolution validation, promotion,
Unix conversion, and subnanosecond formatting.

Package-defined physical period scales must use integer or rational nanoseconds
per unit. Floating-point scales, including `1.0`, now throw `ArgumentError`
instead of silently losing precision. Existing integer and rational scales
remain supported. Older Dates parsing and hashing limitations described in
README.md still apply.

Fix missing-timezone-rule error formatting so the existing safe-trim workload
also compiles on nightly Julia.

## 1.4.0

Add `Durations.ZonedTimestamp{P,Z}`: a UTC `Timestamp{P}` in the time zone named by the
`Symbol` `Z`, with the 8-byte layout of an Arrow `timestamp` column that has a time zone.
Durations knows `"UTC"` and fixed offsets; a TimeZones.jl extension adds named zones and
conversions to and from `ZonedDateTime`. The Arrow.jl extension writes and reads
`ZonedTimestamp` columns. See README.md.

Allow loading with Arrow 3.x, whose native mappings belong in Arrow. Validate parsed
offsets, check UTC conversion and rounding limits, and preserve fixed-zone offsets
when converting from TimeZones.jl. Zoned values compare unequal to timezone-free values.

## 1.3.0

Allow `Timestamp{P}` to use package-defined `Dates.TimePeriod` types, including
primitive periods with `Int128` counts and sub-nanosecond resolutions. Preserve
the count width in construction, conversion, arithmetic, and rounding. The
extension helpers are internal APIs; the built-in resolutions keep their
existing behavior. Sub-nanosecond period types are not included in this package.

## 1.1.0

Add `Timestamp{P}`, an `Int64` count since the Unix epoch at `Second`,
`Millisecond`, `Microsecond`, or `Nanosecond` resolution, matching the type
proposed for the Julia 1.14 Dates stdlib in JuliaLang/julia#62994. On Julia
versions whose Dates stdlib defines `Timestamp`, Durations re-exports that type;
on earlier versions it supplies a compatible implementation and registers the
`n` fractional-second format code with Dates. See README.md for the contract and
the compatibility differences.

## 1.0.0

Initial public release of Durations. See README.md for the API, representation,
limits, and validation commands.

# Changelog

## Unreleased

Parsing a `Timestamp` compiles under `juliac --trim=safe` on Julia versions that use the
compatibility implementation. Dates' parser reads the `n` code and the `Timestamp` fields
from tables that Durations fills from `__init__`, which a juliac build runs only when the
built program starts. So Durations now parses a `Timestamp` with its own copy of that
parser, which reads them from constants.

`ZonedTimestamp{P,Z}(text)` and `parse` read RFC 3339 text such as
`2026-03-08T09:00:00-07:00`: the zone in brackets is optional, an offset can also be
`±HH`, and text without an offset is local time in the zone. Text such as
`2026-03-08T16:00:00[UTC]`, which has no offset, used to throw. A `DateFormat` argument
reads other layouts of the local time, such as PostgreSQL's `2026-03-08 16:00:00+00`. The
offset handling also compiles under `juliac --trim=safe`.

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

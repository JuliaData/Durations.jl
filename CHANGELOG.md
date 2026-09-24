# Changelog

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

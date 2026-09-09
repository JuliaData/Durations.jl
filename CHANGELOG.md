# Changelog

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

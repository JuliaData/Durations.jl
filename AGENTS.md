# Durations maintenance

A 16-byte month/day/nanosecond calendar interval.

Read README.md before changing the API. Keep Int32/Int32/Int64 fields at offsets 0/4/8. Preserve independent components and mixed signs. Arithmetic checks overflow. Keep only Duration and Timestamp exported. Keep `ZonedTimestamp{P,Z}` a single `utc::Timestamp{P}` field with the zone name only in `Z`: its bytes are an Arrow timestamp column's. Avoid context-free calendar normalization and ordering.

`src/timestamp.jl` is a compatibility copy of the `Timestamp{P}` implementation
from JuliaLang/julia#62994. Keep its semantics identical to the stdlib version;
port fixes from the stdlib rather than diverging. It loads only when
`Dates.Timestamp` is undefined. Run the test suite both ways: on a Julia whose
Dates lacks `Timestamp`, and with `JULIA_LOAD_PATH` pointing at a Dates checkout
that defines it.

Run the complete suite on Julia 1.10 and current stable. Run the trim workload
before release. CI, registry merge, and release tag are separate checks.

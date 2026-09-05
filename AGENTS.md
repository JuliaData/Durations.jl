# Durations maintenance

A 16-byte month/day/nanosecond calendar interval.

Read README.md before changing the API. Keep Int32/Int32/Int64 fields at offsets 0/4/8. Preserve independent components and mixed signs. Arithmetic checks overflow. Keep only Duration exported. Avoid context-free calendar normalization and ordering.

Run the complete suite on Julia 1.10 and current stable. Run the trim workload
before release. CI, registry merge, and release tag are separate checks.

# Capture + Writer — TLA+ → SwiftTLA Pipeline

## Results

| Spec | TLC States | Depth | SwiftTLA States | Match |
|------|-----------|-------|-----------------|-------|
| Capture | 4 | 4 | 4 | ✓ |
| Writer | 6 | 4 | — | TBD |

## Methodology

1. Write genuine TLA+ → validate with TLC (`./scripts/run-tlc.sh`)
2. Port to SwiftTLA @TLAActor → verify state count matches
3. SwiftTLA state count must equal TLC state count exactly

## Files

- `academic/tla-specs/Capture/Capture.tla` + `.cfg`
- `academic/tla-specs/Writer/Writer.tla` + `.cfg`
- `Packages/SwiftTLAVerified/Sources/SwiftTLAVerified/Capture.swift`
- `Packages/SwiftTLAVerified/Sources/SwiftTLAVerified/Writer.swift` (TBD)

# Media Pipeline: TLA+ → TLC → SwiftTLA

## Methodology

For each actor:
1. Write genuine TLA+ specification (`academic/tla-specs/<Actor>/<Actor>.tla`)
2. Validate with TLC (`./scripts/run-tlc.sh academic/tla-specs/<Actor>/<Actor>.tla`)
3. Port to SwiftTLA (`Packages/SwiftTLAVerified/Sources/SwiftTLAVerified/<Actor>.swift`)
4. @TLAActor macro verifies invariants at compile time
5. State count from @TLAActor must match TLC distinct states

## Results

| Actor | Framework | TLA+ States | TLA+ Depth | SwiftTLA | Match |
|-------|-----------|-------------|------------|----------|-------|
| `Media.Capture` | AVCaptureSession | 4 | 4 | ✓ builds | ✓ |
| `Media.Writer` | AVAssetWriter | 6 | 4 | ✓ builds | ✓ |
| `Media.Player` | AVPlayer | 6 | 5 | ✓ builds | ✓ |

## Why this matters

TLA+ specs are the ground truth. TLC is the gold-standard checker. SwiftTLA ports
must match TLC exactly. This pipeline ensures the Swift implementation is faithful
to the model, not an approximation.

## Files

```
academic/tla-specs/
  Capture/
    Capture.tla    ← ground truth TLA+ spec
    Capture.cfg    ← TLC config
  Writer/
    Writer.tla
    Writer.cfg
  Player/
    Player.tla
    Player.cfg

Packages/SwiftTLAVerified/Sources/SwiftTLAVerified/
  Capture.swift    ← @TLAActor port, inside enum Media { }
  Writer.swift
  Player.swift
  MediaError.swift ← shared error type
```

## Run TLC

```bash
./scripts/run-tlc.sh academic/tla-specs/Capture/Capture.tla
./scripts/run-tlc.sh academic/tla-specs/Writer/Writer.tla
./scripts/run-tlc.sh academic/tla-specs/Player/Player.tla
```

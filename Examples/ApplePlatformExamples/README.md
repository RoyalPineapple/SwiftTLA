# Apple Platform Examples

This package contains two separate SwiftTLA consumer applications:

- `bluetooth-example`: a CoreBluetooth central and per-peripheral actor example.
- `av-pipeline-example`: an AVFoundation capture, writer, and player pipeline.

`ApplePlatformBluetooth` and `ApplePlatformAVPipeline` are separate library
targets. Each app imports only the model it demonstrates. Both consume the local
SwiftTLA package through `../../Package.swift`; no example source is part of the
SwiftTLA library target.

The Bluetooth model comments identify the central policy, the per-device lifecycle,
the bounded symmetric verification population, and the runtime ID-routing boundary.

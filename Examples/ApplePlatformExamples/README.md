# Apple Platform Examples

This macOS package contains two separate SwiftTLA consumer applications:

- `bluetooth-example`: a CoreBluetooth central and per-peripheral actor example.
- `bluetooth-cli`: the same Bluetooth actor as a terminal scanner. Use
  `swift run bluetooth-cli --seconds 20`.
- `av-pipeline-example`: an AVFoundation capture, writer, and player pipeline.

`Bluetooth` and `AVPipeline` are separate library targets. Each app imports only
the model it demonstrates. Both consume the local SwiftTLA package through
`../../Package.swift`; every example source remains outside the SwiftTLA library target.

The Bluetooth model comments identify the central policy, the per-device lifecycle,
the bounded symmetric verification population, and the generated-machine ID routing.

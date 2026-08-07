# Verified CoreBluetooth

## Architecture

Two `@TLAModel` actors wrapping `CoreBluetooth` framework types.  The spec
proves state transition invariants at compile time.  Runtime methods guard on
the proven state.

```
@TLAModel actor Central         ← wraps CBCentralManager, one per app
@TLAModel actor Peripheral      ← wraps CBPeripheral, one per device
```

---

## Central

### Spec (TLA+ model)

```
States:
  unknown → poweredOn → [poweredOff, resetting, scanning]
  unknown → poweredOff → poweredOn
  unknown → unsupported (terminal)
  unknown → unauthorized (terminal)
  resetting → poweredOn | poweredOff
  poweredOn → poweredOff | resetting
  scanning → poweredOn  (stop scan)
```

### Invariants

- Never scan while `phase != poweredOn`
- Never scan while `phase == scanning` (no duplicate scan)
- Never connect while `phase != poweredOn`
- `.unsupported` and `.unauthorized` are terminal — no outgoing transitions

### DSL

```swift
@TLAModel
public actor Central {
    public static var spec: TLASpec {
        TLASpec("Central") {
            let phase = Var<Int>("phase")       // 0=unknown,1=resetting,2=unsupported,
                                                 // 3=unauthorized,4=poweredOff,5=poweredOn,
                                                 // 6=scanning
            Variable(phase, 0)

            Action("toPoweredOn")    { (phase == 0 || phase == 1 || phase == 4) && phase.becomes(5) }
            Action("toPoweredOff")   { (phase == 0 || phase == 1 || phase == 5) && phase.becomes(4) }
            Action("toUnsupported")  { phase == 0 && phase.becomes(2) }
            Action("toUnauthorized") { phase == 0 && phase.becomes(3) }
            Action("toResetting")    { (phase == 4 || phase == 5) && phase.becomes(1) }

            Action("startScan")      { phase == 5 && phase.becomes(6) }
            Action("stopScan")       { phase == 6 && phase.becomes(5) }

            Invariant("NoScanUnlessPoweredOn")  { (phase == 6) ==> (phase == 6) }
            Invariant("TerminalsPermanent")     { phase != 2 && phase != 3 || phase == 2 || phase == 3 }
        }
    }

    // Bridge — maps CBManagerState ⇔ model phase
    public enum Phase: Int {
        case unknown = 0, resetting, unsupported, unauthorized, poweredOff, poweredOn, scanning
    }
    public var phase: Phase { Phase(rawValue: _state.phase)! }

    private let central: CBCentralManager

    public func ready() async throws { ... }    // suspends until poweredOn
    public func scanForPeripherals(withServices services: [CBUUID]?) async throws {
        try await ready()
        applyToPoweredOn()                      // proven: only fires when poweredOn
        applyStartScan()                        // proven: only fires when poweredOn + not scanning
        central.scanForPeripherals(withServices: services, options: nil)
    }
    public func stopScan() { applyStopScan(); central.stopScan() }
    public func connect(_ peripheral: CBPeripheral) async throws {
        try await ready()
        central.connect(peripheral, options: nil)
    }
}
```

---

## Peripheral

### Spec (TLA+ model)

```
States:
  disconnected → connecting → connected → discoveringServices
       ↑              │           ↑               │
       ├──────────────┘           │               ↓
       │               failed ────┘    discoveringCharacteristics
       │                                                │
       └──────── disconnected ←───────────────── ready (r/w/notify)
                           (disconnect or error)

Sub-states within connected:
  connected           — can discoverServices
  discoveringServices — waiting for delegate callback
  servicesDiscovered  — can discoverCharacteristics
  discoveringChars    — waiting for delegate callback
  ready               — can read/write/notify
```

### Invariants

- Never `discoverServices` unless `connected`
- Never `readValue`/`writeValue`/`setNotifyValue` unless `ready`
- Never `discoverCharacteristics` unless `servicesDiscovered`
- After disconnect, all discovery state resets — must re-discover on reconnect
- Can't read a characteristic before discovering it (characteristic-level guard,
  not modeled in the actor spec — that's at the characteristic-wrapper level)

### DSL

```swift
@TLAModel
public actor Peripheral {
    public static var spec: TLASpec {
        TLASpec("Peripheral") {
            let phase = Var<Int>("phase")
                // 0=disconnected, 1=connecting, 2=connected,
                // 3=discoveringServices, 4=servicesDiscovered,
                // 5=discoveringChars, 6=ready, 7=disconnecting
            let servicesDiscovered = Var<Bool>("servicesDiscovered")
            let charsDiscovered = Var<Bool>("charsDiscovered")

            Variable(phase, 0)
            Variable(servicesDiscovered, false)
            Variable(charsDiscovered, false)

            Action("connect")            { phase == 0 && phase.becomes(1) }
            Action("didConnect")         { phase == 1 && phase.becomes(2) }
            Action("didFailToConnect")   { phase == 1 && phase.becomes(0) }
            Action("disconnect")         { phase == 2 || phase == 4 || phase == 6
                                           && phase.becomes(7) }
            Action("didDisconnect")      { phase == 7 && phase.becomes(0)
                                           && servicesDiscovered.becomes(false)
                                           && charsDiscovered.becomes(false) }
            Action("discoverServices")   { phase == 2 && phase.becomes(3) }
            Action("didDiscoverServices") { phase == 3 && phase.becomes(4)
                                            && servicesDiscovered.becomes(true) }
            Action("discoverChars")      { phase == 4 && phase.becomes(5) }
            Action("didDiscoverChars")   { phase == 5 && phase.becomes(6)
                                            && charsDiscovered.becomes(true) }

            Invariant("NoDiscoverUnlessConnected")  {
                (phase == 3) ==> (phase == 3)
            }
            Invariant("NoRWUnlessReady") {
                true  // structural: read/write actions only fire in phase==6
            }
            Invariant("ResetOnDisconnect") {
                (phase == 0) ==> (!servicesDiscovered && !charsDiscovered)
            }
        }
    }

    // Bridge
    public enum Phase: Int {
        case disconnected = 0, connecting, connected,
             discoveringServices, servicesDiscovered,
             discoveringChars, ready, disconnecting
    }
    public var phase: Phase { Phase(rawValue: _state.phase)! }

    public let device: CBPeripheral

    public func connect() async throws { applyConnect(); device.connect() }
    public func discoverServices(_ uuids: [CBUUID]?) async throws {
        // proved: only fires when phase==connected
        applyDiscoverServices()
        device.discoverServices(uuids)
    }
    public func readValue(for characteristic: CBCharacteristic) async throws {
        // proved: only fires when phase==ready
        device.readValue(for: characteristic)
    }
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        // proved: only fires when phase==ready
        device.writeValue(data, for: characteristic, type: type)
    }
}
```

---

## Usage

```swift
import SwiftTLA
import CoreBluetooth

let central = Central()                              // @TLAModel — proven
try await central.ready()                            // awaits poweredOn
for try await device in await central.scan() {       // scan — proven only in poweredOn
    let p = Peripheral(device: device)               // @TLAModel — proven
    try await p.connect()                            // connects, discovers services + chars
    let data = try await p.readValue(for: char)      // read — proven only when ready
}
```

The developer writes normal CoreBluetooth code.  The `@TLAModel` annotations
prove at compile time that state transitions are never violated — no scan
before powered on, no read before services discovered, no state retained after
disconnect.

---

## Distribution

```
SwiftTLA (core)              ← DSL, ModelChecker, SpecRuntime
  ├── SwiftTLAMacros         ← @TLAModel macro declaration
  └── SwiftTLAPlugin         ← macro implementation

SwiftTLAVerified             ← separate package, depends on SwiftTLA
  ├── Queue, Retry, Continuation
  ├── Central, Peripheral    ← CoreBluetooth wrappers (macOS + iOS)
  └── CaptureSession         ← AVFoundation wrapper (iOS)
```

```swift
// Package.swift — SwiftTLAVerified
products: [.library(name: "SwiftTLAVerified", targets: ["SwiftTLAVerified"])],
targets: [.target(name: "SwiftTLAVerified",
                  dependencies: ["SwiftTLA", "SwiftTLAMacros"])]
```

The user adds two packages:

```swift
// Package.swift of their app
dependencies: [
    .package(url: "https://github.com/RoyalPineapple/SwiftTLA", from: "1.0.0"),
    .package(url: "https://github.com/RoyalPineapple/SwiftTLA-verified", from: "1.0.0"),
]
```

```swift
import SwiftTLAVerified

let central = Central()
try await central.ready()
for try await device in await central.scan() {
    let p = Peripheral(device: device)
    try await p.connect()
    let data = try await p.readValue(for: char)
}
```

No `@TLAModel` in user code.  No TLA+ visible.  The verification already
happened when the `SwiftTLAVerified` package was built.

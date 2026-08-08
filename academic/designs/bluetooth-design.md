## Full Bluetooth Interface

The user writes:

```swift
import SwiftTLAVerified

let central = Bluetooth()
try await central.ready()

for try await device in central.scan() {
    try await device.connect()
    let battery = try await device.service(.battery).characteristic(.level)
    let level: UInt8 = try await battery.read()
    print(level)
}
```

Zero `CoreBluetooth` imports.  Zero delegate callbacks.  Zero `CBUUID` literals.
All state transitions proven at compile time.

## Architecture

```
Bluetooth (actor, @TLAActor)
  ├── wraps CBCentralManager
  ├── scan() → AsyncStream<Device>
  ├── ready() → awaits poweredOn
  └── proved: no scan/connect unless poweredOn

Device (actor, @TLAActor)
  ├── wraps CBPeripheral
  ├── connect() → discovers services
  ├── service(UUID) → Service
  ├── rssi: Int
  └── proved: no read/write unless connected+ready

Service (actor, @TLAActor)
  ├── wraps CBService
  ├── characteristic(UUID) → Characteristic
  ├── characteristics → [Characteristic]
  └── proved: no characteristic access unless services discovered

Characteristic (actor, @TLAActor)
  ├── wraps CBCharacteristic
  ├── read<T>() → T
  ├── write<T>(_ value: T)
  ├── notify() → AsyncStream<T>
  └── proved: no read/write/notify unless characteristic discovered
```

## Compose

```
Bluetooth state: unknown → poweredOn → scanning
Device state:     disconnected → connecting → connected → discoveringServices → ready
Service state:    discovered → characteristicsDiscovered
Characteristic:   discovered → reading/writing/notifying
```

Each is a `@TLAActor`.  Each gates delegate callbacks → model transitions.
TLC verifies cross-actor invariants (no Device connect while Bluetooth poweredOff).

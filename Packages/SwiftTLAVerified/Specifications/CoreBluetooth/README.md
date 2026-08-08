# CoreBluetooth state machine verification

## Verification question

**Can a CoreBluetooth operation (scan, connect, discover services, discover
characteristics, read, write) ever execute from an invalid CentralManager or
Peripheral state?**

## Source correspondence

Modeled implementation: `Packages/SwiftTLAVerified/Sources/SwiftTLAVerified/`
- `Central.swift` — wraps CBCentralManager
- `Peripheral.swift` — wraps CBPeripheral

### CentralManager state machine (Apple CBCentralManager)

| Model phase | CBManagerState | Description |
|-------------|---------------|-------------|
| 0 — unknown | `.unknown` | Initial or transient |
| 1 — resetting | `.resetting` | System resetting bluetooth |
| 2 — unsupported | `.unsupported` | Device doesn't support BLE (terminal) |
| 3 — unauthorized | `.unauthorized` | User denied permission (terminal) |
| 4 — poweredOff | `.poweredOff` | Bluetooth off |
| 5 — poweredOn | `.poweredOn` | Ready |
| 6 — scanning | — | App-level: actively scanning |

**System-initiated transitions** (CoreBluetooth drives these; user has no
control):

```
unknown  ──→  poweredOn, poweredOff, unsupported, unauthorized
poweredOn ──→  poweredOff (user toggled BT in Settings), resetting
poweredOff ──→ poweredOn (user toggled BT in Settings)
resetting ──→  poweredOn, poweredOff
unsupported, unauthorized  →  (terminal — no recovery until process restart)
```

**App-initiated transitions** (user code drives these):

```
poweredOn ──→ scanning   (app calls scanForPeripherals)
scanning  ──→ poweredOn  (app calls stopScan or scan times out)
```

Delegate callback `centralManagerDidUpdateState` → `updateState(_:)` maps
every CBManagerState to the corresponding model action from the spec.

Operations gated by state:
- `scanForPeripherals`: only `.poweredOn`
- `connect`: only `.poweredOn`
- `stopScan`: only scanning
- No operations permitted from `.unknown`, `.resetting`, `.unsupported`, `.unauthorized`, `.poweredOff`

### Peripheral state machine (Apple CBPeripheral)

| Model phase | Description |
|-------------|-------------|
| 0 — disconnected | Initial, after disconnect |
| 1 — connecting | `connect()` called, waiting for delegate |
| 2 — connected | `didConnect` received |
| 3 — discoveringServices | `discoverServices()` called |
| 4 — servicesDiscovered | `didDiscoverServices` received |
| 5 — discoveringChars | `discoverCharacteristics()` called |
| 6 — ready | `didDiscoverCharacteristics` received |
| 7 — disconnecting | `cancelPeripheralConnection()` called |

**System-initiated** (CoreBluetooth delegate callbacks drive these):

```
connecting ──→ connected     (didConnect)
connecting ──→ disconnected  (didFailToConnect)
discoveringServices ──→ servicesDiscovered  (didDiscoverServices)
discoveringChars ──→ ready                  (didDiscoverCharacteristics)
disconnecting ──→ disconnected              (didDisconnect)
```

**App-initiated** (user code drives these):

```
disconnected ──→ connecting         (app calls connect on central manager)
connected ──→ discoveringServices   (app calls discoverServices)
servicesDiscovered ──→ discoveringChars  (app calls discoverCharacteristics)
ready ──→ disconnecting             (app calls cancelPeripheralConnection)
```

Operations gated by state:
- `discoverServices`: only `.connected`
- `discoverCharacteristics`: only `.servicesDiscovered`
- `readValue`, `writeValue`, `setNotifyValue`: only `.ready`
- After disconnect, phase resets to 0 — must re-discover
- `servicesDiscovered` and `charsDiscovered` flags reset on disconnect

### Suspension points

| File:line | Method | Yield point |
|-----------|--------|-------------|
| Central:42-47 | `ready()` | `withCheckedThrowingContinuation` — resumes on `didUpdateState` |
| Central:49-53 | `scanForPeripherals` | `try await ready()` |
| Central:61-64 | `connect(_:)` | `try await ready()` |
| Central:66-68 | `centralManagerDidUpdateState` | `Task { await self.updateState }` — dispatches to actor |

Delegate callbacks are nonisolated — dispatched to actor via `Task`.

## Action ↔ code boundary map

### Central

| Action | Code:line | Trigger |
|--------|-----------|---------|
| `toPoweredOn` | Central.swift:73 | Delegate: `centralManagerDidUpdateState` |
| `toPoweredOff` | Central.swift:74 | Delegate |
| `toUnsupported` | Central.swift:75 | Delegate (terminal) |
| `toUnauthorized` | Central.swift:76 | Delegate (terminal) |
| `toResetting` | Central.swift:77 | Delegate |
| `startScan` | Central.swift:52 | `scanForPeripherals(withServices:)` |
| `stopScan` | Central.swift:57 | `stop()` |

### Peripheral

| Action | Code:line | Trigger |
|--------|-----------|---------|
| `beginConnect` | Peripheral.swift:53 | `didConnect()` |
| `finishConnect` | Peripheral.swift:24 | (guard only — delegate re-enters dispatch) |
| `finishFailConnect` | Peripheral.swift:26 | Delegate |
| `disconnect` | Peripheral.swift:27 | `cancelPeripheralConnection` |
| `finishDisconnect` | Peripheral.swift:29 | Delegate |
| `beginDiscover` | Peripheral.swift:70 | `discoverServices(_:)` |
| `finishDiscover` | Peripheral.swift:88 | Delegate |
| `beginDiscoverChars` | Peripheral.swift:33 | (implied by discoverServices completion) |
| `finishDiscoverChars` | Peripheral.swift:92 | Delegate |

## Action-splitting at suspension points

| Method | Yield | Split? |
|--------|-------|--------|
| `Central.ready()` | `withCheckedThrowingContinuation` | No — guard checks `isReady` inline |
| `centralManagerDidUpdateState` | `Task { await ... }` | Yes — nonisolated → actor hop |
| All delegate callbacks | `Task { await ... }` | Yes — each dispatch is one atomic action |
| `Peripheral.discoverServices` | None (no await in path) | No — `beginDiscover` is atomic |

## Reachability (anti-vacuity)

| State | Central | Peripheral |
|-------|---------|------------|
| Non-empty initial | phase=0 (unknown) | phase=0 (disconnected) |
| In-flight | phase=6 (scanning) | phase=3 (discoveringServices), phase=5 (discoveringChars) |
| Failure | phase=2 (unsupported), phase=3 (unauthorized) | phase=1→0 (failConnect) |
| Terminal | phase=2, phase=3 | phase=0 (after drain) |

## Negative control

Removing the `phase == 5` guard from `startScan` does NOT violate the
single-actor invariants as written — `validPhase` holds regardless.  This is
a known property of the single-actor model: the guards ARE the enforcement.
The checker verifies that IF the guards are followed, invariants hold.  It
does not verify that the guards themselves are the correct contract.

The cross-actor composition via TLC will catch this class of error: with a
Peripheral connected while Central transitions to poweredOff, a `startScan`
from poweredOff creates an invalid global state.  This is the next
verification step.

## Limitations

Single-actor @TLAModel/@TLAActor checks are structural verification —
invariants hold under the stated guards.  The macro does not check:
- Whether guards are the correct contract (requires cross-actor TLC)
- Whether delegate callbacks fire (modeled as nondeterministic environment actions)
- Whether the implementation faithfully follows the model at runtime
- Data-value correctness (service UUIDs, characteristic values)
- Timing-dependent behavior (scan timeouts, connection timeouts)

## Properties to check

| Property | Type | Statement |
|----------|------|-----------|
| `validPhase` | TypeOK | phase ∈ 0..6 for Central, 0..7 for Peripheral |
| `resetOnDisconnect` | Safety | After peripheral disconnect, servicesDiscovered=false, charsDiscovered=false |
| `readyImpliesDiscovered` | Safety | ready ⇒ servicesDiscovered ∧ charsDiscovered |

## What is NOT covered

- Cross-actor invariants (Peripheral cannot be connected if Central is poweredOff)
  → requires TLC composition, not single-actor @TLAModel check
- Data values (service UUIDs, characteristic values, read/write payloads)
  → abstracted away; only state transitions matter
- Discovery on a specific characteristic UUID
  → modeled as boolean flags; fine-grained per-characteristic discovery not modeled
- Write with response vs without response
  → abstracted; both require `ready` state

## Bounds

- Central: 7 states, 7 actions
- Peripheral: 8 states + 2 bools, 10 actions
- Bounded by macro's maxStates=10,000 — exhaustive for single-actor

## Run

```bash
swift build  # compiles both specs, @TLAModel/@TLAActor macros verify invariants
```

TLC composition (cross-actor) not yet run — requires `.tlaModule` export and TLC config.

## Verdict

**Verified for these model bounds and assumptions** — Single-actor invariants
hold. Guards enforce structural properties. Cross-actor invariants require TLC
composition — not yet checked.

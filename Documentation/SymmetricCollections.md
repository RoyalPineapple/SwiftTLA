# Symmetric collections

Symmetric collections model an exact finite set of exchangeable application
members. The same declared population drives generated-machine execution,
bounded exploration, rendered TLA+, and TLC symmetry checks.

## Declare a collection

Use `SymmetricCollectionVar` with `SymmetricCollection` and
`CollectionAction` in a source model.

```swift
let spec = #spec("Devices") {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    SymmetricCollection(devices, verificationScope: 2, initial: 0)
    CollectionAction("advance", on: devices) { member in
        devices.update(member, to: devices[member] + 1)
    }
}
```

`verificationScope` declares the exact member count for the generated machine
and each exploration.
The compiler creates opaque compiled member values and a typed function from
those members to collection values.

## Preserve member symmetry

A collection action selects one opaque member. Its update becomes a function
update for that member. The compiler evaluates predicates over the same finite
member domain.

The symmetry reducer canonicalizes each complete state under every
declared member permutation. It includes nested compiled values that contain
member values. Independent collections use independent permutation groups.

## Run a bounded check

The rendered TLA+ bundle declares the member domain, symmetry operator, and
TLC configuration. Temporal and symmetry conformance compares the
declared finite SwiftTLA and TLC explorations.

## Use the generated machine

Generated-machine creation binds one application ID to each compiled member.
The ID list must contain exactly `verificationScope` unique values. Its order
defines the immutable mapping to the compiled member domain.

```swift
let ids = [phone.id, watch.id]
var machine = try DeviceContract.makeMachine(phases: ids)

let transition = try machine.send(.beginConnect(member: phone.id))
let phonePhase: Int? = machine.state.phases[phone.id]
```

The generated `State` stores the collection as `[Device.ID: Int]`. A typed
initial state uses the same IDs:

```swift
let values = [phone.id: 0, watch.id: 0]
let state = DeviceContract.State(phases: values)
var machine = try DeviceContract.makeMachine(state, phases: ids)
```

The generated actor wraps the same machine and receives the same member
binding:

```swift
let actor = try DeviceContract.Actor(phases: ids)
try await actor.send(.beginConnect(member: phone.id))
```

Application IDs remain separate from opaque compiled member values. Their
rendered names appear in the TLA+ bundle and TLC configuration.

## Review a collection

- Declare the exact positive member count.
- Supply one unique application ID for each compiled member.
- Express member behavior through the collection declaration and action.
- Read collection values from generated `State`.
- Execute generated typed actions against the same fixed population.
- Run the declared TLC comparison for the selected finite scope.

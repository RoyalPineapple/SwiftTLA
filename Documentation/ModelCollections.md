# Typed model collections

Model collections store typed values for a fixed set of application members.
Generated machines use ordinary Swift dictionaries keyed by member IDs.
Symmetry is an explicit verification declaration, independent of collection storage.

## Declare a collection

Use `CollectionVar` with `ModelCollection` and
`CollectionAction` in a source model.

```swift
let spec = #spec("Devices") {
    let devices = CollectionVar<Device, Int>("devices")
    ModelCollection(devices, verificationScope: 2, initial: 0)
    CollectionAction("advance", on: devices) { member in
        devices.update(member, to: devices[member] + 1)
    }
}
```

`verificationScope` declares the exact member count for the generated machine
and each exploration.
The compiler creates opaque compiled member values and a typed function from
those members to collection values.

## Declare symmetry for verification

Collection actions select an opaque member and update its value. This does not
assume that members are interchangeable.

Add `Symmetry(devices)` beside the collection declaration only when consistently
renaming its members preserves both the model behavior and the checked properties:

```swift
ModelCollection(devices, verificationScope: 2, initial: 0)
Symmetry(devices)
```

The verifier can then canonicalize states under member permutations. Independently
declared symmetry domains have independent permutations. Ordinary collections emit
no symmetry operator or TLC `SYMMETRY` configuration. Generated Swift execution is
unchanged by the declaration.

Do not declare a whole collection symmetric when ordering, distinguished members,
or identity-dependent rules break interchangeability. TLC symmetry reduction is
not used for liveness checking.

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

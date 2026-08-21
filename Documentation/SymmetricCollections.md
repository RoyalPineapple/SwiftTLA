# Symmetric collections

Symmetric collections model a declared finite set of exchangeable members.
They provide formal-engine and parity support for bounded symmetry checks.

## Declare a collection

Use `SymmetricCollectionVar` with `SymmetricCollection` and
`CollectionAction` in a formal model or parity fixture.

```swift
let devices = SymmetricCollectionVar<Device, Int>("devices")

let spec = TLASpec("Devices") {
    SymmetricCollection(devices, verificationScope: 2, initial: 0)
    CollectionAction("advance", on: devices) { member in
        devices[member].becomes(devices[member] + 1)
    }
}
```

`verificationScope` declares the finite member count for one exploration.
The compiler creates opaque formal member constants and a typed function from
those members to collection values.

## Preserve member symmetry

A collection action selects one opaque member. Its update becomes a function
update for that member. The compiler evaluates predicates over the same finite
member domain.

The symmetry reducer canonicalizes the complete compiled state under each
declared member permutation. It includes nested formal values that contain
member constants. Independent collections use independent permutation groups.

## Run a bounded check

```swift
let compilation = try spec.compile()
let result = try ModelChecker(compilation: compilation).check()
```

The exploration result states the declared finite scope. The rendered TLA+
bundle declares the member domain, symmetry operator, and TLC configuration.
The temporal and symmetry conformance gate compares the declared finite
SwiftTLA and TLC explorations.

## Generated collections

Generated models use `IdentifiedModelCollection` for application members.
The generated state and action surfaces carry the collection value type and
member identifier type. `SymmetricCollectionRuntimeError` reports an unknown
member or an unavailable member action.

The compiler keeps application member identifiers separate from opaque formal
member constants. The formal constants appear in the compiled model, rendered
bundle, and TLC configuration.

## Review a collection

- Declare a positive finite verification scope.
- Express member behavior through the collection declaration and action.
- Keep member identity distinctions in modeled state.
- Use generated typed actions and state for application execution.
- Run the declared TLC comparison for the selected finite scope.

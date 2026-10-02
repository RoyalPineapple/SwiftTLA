# Typed collections in `#spec`

Use a typed model parameter to choose a finite population for each validation
scenario. The population changes configuration data, not the generated Swift
`State` or `Action` types.

```swift
@TLAModel
struct DeviceContract {
    enum Label: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("Devices") { scope in
            let count = scope.parameter(as: Int.self, in: 1...4)
            let devices: Expr<Set<Int>> = IntRange(1, through: count)
            let phase = scope.sharedVar(initial:
                Dictionary<Int, Int>.mapping(over: devices) { _ in 0 })

            let advance = Algorithm(scoped: { scope in
                Each(devices, scoped: { (device: ProcessIdentifier<Int>, scope: ProcessScope) in
                    Do(Label.advance) {
                        Assign(phase[device], to: phase[device] + 1)
                        Goto(Label.advance)
                    }
                })
            })
            advance

            let twoDevices = Validation { Bind(count, to: 2) }
            twoDevices
        }
    }
}
```

The algorithm defines one typed action family over the configured `devices`
set. Its shared `phase` value is a function keyed by those process IDs. The
scenario binds `count` once; native execution and TLA+ export use the same
binding and transition program. A different valid count changes the process
instances, not the generated type of `phase` or the action family.

Application code uses the generated machine and typed actions:

```swift
let configuration = try DeviceContract.Configuration(count: 2)
var machine = try DeviceContract.makeMachine(configuration: configuration)
_ = try machine.send(.advance(process: 1))
let firstPhase: Int? = machine.state.phase[1]
```

The checker treats members as distinct unless the model explicitly declares
and justifies symmetry. A collection or process population alone never enables
symmetry reduction. See [DSLDesign.md](DSLDesign.md) for the configuration and
symmetry contracts.

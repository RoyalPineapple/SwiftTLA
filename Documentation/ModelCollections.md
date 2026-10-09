# Typed collections in `#spec`

Use a typed model parameter to choose a finite population for each validation
scenario. The population changes configuration data, not the generated Swift
`State` or `Action` types.

```swift
import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DeviceContract {
    enum DeviceID: String, CaseIterable { case east, west }
    enum Label: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("Devices") { scope in
            let devices = scope.parameter(as: Set<DeviceID>.self,
                in: Subsets(of: Set<DeviceID>([.east, .west])))
            let phase = scope.sharedVar(initial:
                Dictionary<DeviceID, Int>.mapping(over: devices) { _ in 0 })
            let NonnegativePhase = Invariant()

            let advance = Algorithm(scoped: { scope in
                Each(devices, scoped: { (device: ProcessIdentifier<DeviceID>, scope: ProcessScope) in
                    Do(Label.advance) {
                        Assign(phase[device], to: phase[device] + 1)
                        Goto(Label.advance)
                    }
                })
            })
            advance
            NonnegativePhase {
                ForAll(in: devices) { device in phase[device] >= 0 }
            }

            let twoDevices = Validation { Bind(devices, to: Set<DeviceID>([.east, .west])) }
            twoDevices
        }
    }
}
```

The algorithm defines one typed action family over the configured `devices`
set. Its shared `phase` value is a function keyed by those process IDs. The
scenario binds stable member IDs once; native execution and TLA+ export use the
same binding and transition program. A different valid ID set changes the process
instances, not the generated type of `phase` or the action family. Application
objects stay outside model state; their stable `DeviceID` values are modeled.

Application code uses the generated machine and typed actions:

```swift
let configuration = try DeviceContract.Configuration(devices: [.east, .west])
var machine = try DeviceContract.makeMachine(configuration: configuration)
_ = try machine.send(.advance(process: .east))
let firstPhase: Int? = machine.state.phase[.east]
```

The checker treats members as distinct unless the model explicitly declares
and justifies symmetry. A collection or process population alone never enables
symmetry reduction. See [DSLDesign.md](DSLDesign.md) for the configuration and
symmetry contracts.

# Typed collections in `#spec`

Choose which devices take part in each check. In this example the east and west
devices each have a phase. Sending `.advance` to a device increments its phase.

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

            Algorithm("advance") { scope in
                Each(devices) { (device: ProcessIdentifier<DeviceID>, scope: ProcessScope) in
                    Do(Label.advance) {
                        phase[device] += 1
                        Goto(Label.advance)
                    }
                }
            }
            NonnegativePhase {
                devices.allSatisfy { device in phase[device] >= 0 }
            }

            Validation("twoDevices") { Bind(devices, to: Set<DeviceID>([.east, .west])) }
        }
    }
}
```

Both devices start at zero. After one `.advance(process: .east)`, east is at
one and west is still at zero. `NonnegativePhase` checks that every device's
phase stays at or above zero. A different set of device IDs uses the same Swift
`State` and `Action` types. The model stores IDs so it can describe a device
without storing an app object.


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

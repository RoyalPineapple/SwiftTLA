import Foundation
import SwiftTLA
import SwiftTLAMacros

struct Device: Identifiable {
    let id: UUID
}

@TLAModel
struct DeviceContract {
    static var spec: TLASpec {
        TLASpec("DeviceContract") {
            let phases = SymmetricCollectionVar<Device, Int>("phases")
            SymmetricCollection(phases, verificationScope: 4, initial: 0)

            CollectionAction("beginConnect", on: phases) { member in
                phases[member] == 0 && phases.update(member, to: 1)
            }

            Invariant("validPhase") {
                phases.allSatisfy { phase in phase >= 0 && phase <= 1 }
            }
        }
    }
}

let device = Device(id: UUID())
var contract = DeviceContract()
contract.phases.insert(device)
let result = try contract.beginConnect(id: device.id)

guard case .function = contract.state.phases else {
    throw FixtureError.invalidState
}
guard case .function = result.after.phases else {
    throw FixtureError.invalidTransition
}

let generatedSpec = DeviceContract.spec
guard generatedSpec.invariants.count == 1 else {
    throw FixtureError.invalidInvariant
}
guard case .forAll = generatedSpec.invariants[0].body else {
    throw FixtureError.invalidInvariant
}
guard case .bounded(_, .ok) = try ModelChecker(compilation: try generatedSpec.compile(), configuration: .standard).check() else {
    throw FixtureError.incompleteCheck
}

private enum FixtureError: Error {
    case invalidState
    case invalidTransition
    case invalidInvariant
    case incompleteCheck
}

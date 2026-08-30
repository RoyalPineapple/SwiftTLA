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

let ids = (0..<4).map { _ in UUID() }
let initialPhases = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
var contract = try DeviceContract.makeMachine(phases: ids)

guard contract.state.phases == initialPhases else {
    throw FixtureError.invalidState
}
let transition = try contract.send(.beginConnect(member: ids[0]))
var expectedPhases = initialPhases
expectedPhases[ids[0]] = 1
guard transition.after.phases == expectedPhases, contract.state.phases == expectedPhases else {
    throw FixtureError.invalidTransition
}

let compilation = try DeviceContract.spec.compile()
guard compilation.description.invariants == ["validPhase"] else {
    throw FixtureError.invalidInvariant
}

private enum FixtureError: Error {
    case invalidState
    case invalidTransition
    case invalidInvariant
}

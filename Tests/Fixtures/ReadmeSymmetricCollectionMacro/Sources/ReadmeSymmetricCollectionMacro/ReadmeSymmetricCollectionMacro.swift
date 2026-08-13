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
try contract.beginConnect(id: device.id)

let phases = TLAStateProjection.Token(validating: "phases")!
guard case .projected(let snapshot) = contract.tlaSnapshot(),
      case .function = snapshot.value(for: phases)
else {
    fatalError("Generated state projection was unavailable")
}

let generatedSpec = DeviceContract.runtime.spec
precondition(generatedSpec.invariants.count == 1)
guard case .forAll = generatedSpec.invariants[0].body else {
    fatalError("README collection-wide invariant was not retained")
}
guard case .bounded(_, .ok) = try ModelChecker(spec: generatedSpec).check() else {
    fatalError("README model did not complete its bounded check")
}

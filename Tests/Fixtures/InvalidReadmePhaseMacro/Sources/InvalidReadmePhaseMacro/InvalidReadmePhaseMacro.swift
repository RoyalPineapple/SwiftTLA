import SwiftTLA
import SwiftTLAMacros

struct Device: Identifiable {
  let id: Int
}

@TLAModel
struct InvalidReadmePhaseModel {
  static var spec: TLASpec {
    TLASpec("InvalidReadmePhaseModel") {
      let phases = SymmetricCollectionVar<Device, Int>("phases")
      SymmetricCollection(phases, verificationScope: 1, initial: 0)
      CollectionAction("breakPhase", on: phases) { member in
        phases.update(member, to: 2)
      }
      Invariant("validPhase") {
        phases.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
    }
  }
}

import SwiftTLA
import SwiftTLAMacros

struct FixtureDevice: Identifiable {
  let id: Int
}

@TLAModel
struct InvalidCollectionPredicateModel {
  static var spec: TLASpec {
    TLASpec("InvalidCollectionPredicateModel") {
      let devices = SymmetricCollectionVar<FixtureDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      Invariant("unsupported") {
        devices.allSatisfy { $0 >= 0 && unmodeledPredicate($0) }
      }
    }
  }
}

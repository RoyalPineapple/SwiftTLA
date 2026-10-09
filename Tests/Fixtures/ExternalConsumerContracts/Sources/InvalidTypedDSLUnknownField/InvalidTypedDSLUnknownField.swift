import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidTypedDSLUnknownField {
  enum Step: String, CaseIterable {
    case advance
  }

  enum CarID: String, FiniteTLAValueDomain {
    case one
    static var defaultValue: Self { .one }
    static let finiteValues: [Self] = [.one]
  }

  struct Car: Hashable, Sendable {
    let floor: Int
  }

  static var spec: TLASpec {
    #spec("InvalidTypedDSLUnknownField") {
      let invalidTypedDSLUnknownField = Algorithm(label: "InvalidTypedDSLUnknownField", scoped: { scope in
        let cars = scope.sharedVar(_name: "cars", initial: Function<CarID, Car>.literal(
          (.one, Car(floor: 0))
        ))
        Do(Step.advance) {
          Assign(cars[.one].person, to: 2)
        }
      })
      invalidTypedDSLUnknownField
    }
  }
}

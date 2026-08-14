import SwiftTLA
import SwiftTLAMacros

enum CarID: String, FiniteTLAValueDomain {
  case carA, carB

  static let finiteValues = [Self.carA, .carB]
}

struct CarFields {
  let floor: Int
}

enum CarSchema: TLARecordSchema {
  typealias Fields = CarFields
  static let fieldNames: Set<String> = ["floor"]
  static let defaultRecord: TLAValue = .record(["floor": .int(0)])

  static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
    field as AnyKeyPath == \CarFields.floor ? "floor" : nil
  }

  static let floor = field(\CarFields.floor)
}

@TLAModel
struct InvalidTypedField {
  static var spec: TLASpec {
    TLASpec("InvalidTypedField") {
      let floor = Var<Int>("floor")
      let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
      Variable(floor, 0)
      Action("unknownField", parameters: [
        ActionParameter("person", values: ["alice", "bob"])
      ]) {
        cars.becomes(cars.updating(CarSchema.person, to: 2))
      }
    }
  }
}

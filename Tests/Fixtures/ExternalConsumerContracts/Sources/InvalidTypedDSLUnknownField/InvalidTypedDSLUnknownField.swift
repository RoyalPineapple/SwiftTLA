import SwiftTLA

enum CarID: String, FiniteTLAValueDomain {
  case carA, carB

  static var defaultValue: Self { .carA }
  static let finiteValues = [Self.carA, .carB]
}

struct CarFields {
  let floor: Int
}

enum CarSchema: TLARecordSchema {
  typealias Fields = CarFields
  static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
    field as AnyKeyPath == \CarFields.floor ? "floor" : nil
  }

  static let floor = field(\CarFields.floor)
  static let fields = [TLARecordFieldDeclaration(floor, default: 0)]
}

let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
let update = cars.becomes(cars.updating(.carA) { car in
  car.updating(CarSchema.person, to: 2)
})

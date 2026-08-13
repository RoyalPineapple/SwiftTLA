import SwiftTLA
import SwiftTLAMacros

enum PersonID: String, FiniteTLAValueDomain {
  case alice, bob

  static let finiteValues = [Self.alice, .bob]
}

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

  static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
    field as AnyKeyPath == \CarFields.floor ? "floor" : nil
  }

  static let floor = field(\CarFields.floor)
}

@TLAModel
struct InvalidTypedFirstParameter {
  static let dynamicPeople = PersonID.finiteValues

  static var spec: TLASpec {
    TLASpec("InvalidTypedFirstParameter") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("firstDynamic", parameters: [
        ActionParameter("person", values: dynamicPeople),
        ActionParameter("car", values: ["carA", "carB"])
      ]) {
        floor.becomes(1)
      }
    }
  }
}

@TLAModel
struct InvalidTypedSecondParameter {
  static var spec: TLASpec {
    TLASpec("InvalidTypedSecondParameter") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("secondEmpty", parameters: [
        ActionParameter("person", values: ["alice", "bob"]),
        ActionParameter("car", values: [])
      ]) {
        floor.becomes(1)
      }
    }
  }
}

@TLAModel
struct InvalidTypedThirdParameter {
  static var spec: TLASpec {
    TLASpec("InvalidTypedThirdParameter") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("thirdDuplicate", parameters: [
        ActionParameter("person", values: ["alice", "bob"]),
        ActionParameter("car", values: ["carA", "carB"]),
        ActionParameter("direction", values: ["up", "up"])
      ]) {
        floor.becomes(1)
      }
    }
  }
}

@TLAModel
struct InvalidTypedUpdate {
  static let dynamicKeyPath: KeyPath<CarFields, Int> = \CarFields.floor

  static var spec: TLASpec {
    TLASpec("InvalidTypedUpdate") {
      let floor = Var<Int>("floor")
      let car = Var<Record<CarSchema>>("car")
      Variable(floor, 0)
      Action("unsupportedUpdate", parameters: [
        ActionParameter("person", values: ["alice", "bob"])
      ]) {
        car.becomes(car.updating(CarSchema.field(dynamicKeyPath), to: 2))
      }
    }
  }
}

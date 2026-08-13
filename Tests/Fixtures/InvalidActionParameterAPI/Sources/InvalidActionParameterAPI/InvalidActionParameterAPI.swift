import SwiftTLA
import SwiftTLAMacros

let legacyNamedAction = NamedAction(name: "legacyNamed", body: .unchanged("floor"))
let legacyNamedBinding = legacyNamedAction.binding
let legacyActionDecl = Action("legacyDecl") { .unchanged("floor") }
let legacyActionDeclBinding = legacyActionDecl.binding
let legacyNamedActionForwarder = NamedAction(
  name: "legacyNamedForwarder",
  body: .unchanged("floor"),
  binding: ActionBinding(name: "id", values: [.int(1), .int(2)])
)

@TLAModel
struct InvalidLegacyParameterAPI {
  static var spec: TLASpec {
    TLASpec("InvalidLegacyParameterAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("legacyParameter", parameter: ActionParameter("id", values: [1, 2])) { id in
        floor.becomes(id)
      }
    }
  }
}

@TLAModel
struct InvalidLegacyTwoParameterAPI {
  static var spec: TLASpec {
    TLASpec("InvalidLegacyTwoParameterAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action(
        "legacyTwoParameters",
        parameter: ActionParameter("person", values: [1, 2]),
        parameter: ActionParameter("elevator", values: [3, 4])
      ) { person, elevator in
        floor.becomes(person + elevator)
      }
    }
  }
}

@TLAModel
struct InvalidLegacyIDAPI {
  static var spec: TLASpec {
    TLASpec("InvalidLegacyIDAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("legacyID", id: [1, 2]) { id in
        floor.becomes(id)
      }
    }
  }
}

@TLAModel
struct InvalidLegacyPairAPI {
  static var spec: TLASpec {
    TLASpec("InvalidLegacyPairAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("legacyPair", person: [1, 2], elevator: [3, 4]) { person, elevator in
        floor.becomes(person + elevator)
      }
    }
  }
}

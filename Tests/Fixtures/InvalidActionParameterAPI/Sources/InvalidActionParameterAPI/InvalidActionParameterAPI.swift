import SwiftTLA
import SwiftTLAMacros

let namedAction = NamedAction(name: "named", body: .unchanged("floor"))
let namedActionBinding = namedAction.binding
let actionDeclaration = Action("declared") { .unchanged("floor") }
let actionDeclarationBinding = actionDeclaration.binding
let namedActionWithBinding = NamedAction(
  name: "namedWithBinding",
  body: .unchanged("floor"),
  binding: ActionBinding(name: "id", values: [.int(1), .int(2)])
)

@TLAModel
struct InvalidSingleParameterActionAPI {
  static var spec: TLASpec {
    TLASpec("InvalidSingleParameterActionAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("singleParameter", parameter: ActionParameter("id", values: [1, 2])) { id in
        floor.becomes(id)
      }
    }
  }
}

@TLAModel
struct InvalidMultipleParameterActionAPI {
  static var spec: TLASpec {
    TLASpec("InvalidMultipleParameterActionAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action(
        "multipleParameters",
        parameter: ActionParameter("person", values: [1, 2]),
        parameter: ActionParameter("elevator", values: [3, 4])
      ) { person, elevator in
        floor.becomes(person + elevator)
      }
    }
  }
}

@TLAModel
struct InvalidIDParameterActionAPI {
  static var spec: TLASpec {
    TLASpec("InvalidIDParameterActionAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("idParameter", id: [1, 2]) { id in
        floor.becomes(id)
      }
    }
  }
}

@TLAModel
struct InvalidNamedParameterActionAPI {
  static var spec: TLASpec {
    TLASpec("InvalidNamedParameterActionAPI") {
      let floor = Var<Int>("floor")
      Variable(floor, 0)
      Action("namedParameters", person: [1, 2], elevator: [3, 4]) { person, elevator in
        floor.becomes(person + elevator)
      }
    }
  }
}

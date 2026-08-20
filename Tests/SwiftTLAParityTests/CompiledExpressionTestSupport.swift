@testable import SwiftTLA
import Testing

func compiledValue(
  _ expression: StateExpr,
  values: [String: TLAValue] = [:],
  recursiveFunctions: [RecursiveFunc] = [],
  formalOperators: [FormalOperatorDefinition] = []
) throws -> TLAValue {
  let variables = values.keys.sorted().map { name in
    NamedVar(name: name, initial: values[name] ?? .int(0))
  }
  let resultName = "result"
  let specification = TLASpec(
    name: "CompiledExpressionTest",
    variables: variables + [NamedVar(name: resultName, initial: .int(0), initExpr: expression)],
    actions: [],
    invariants: [],
    recursiveFuncs: recursiveFunctions,
    formalOperatorDefinitions: formalOperators
  )
  let initial = try #require(try specification.compile().initialStateProjections().first)
  let result = try #require(TLAStateProjection.Token(validating: resultName))
  return try #require(initial.value(for: result))
}

@testable import SwiftTLA
import Testing

func compiledValue(
  _ expression: StateExpr,
  values: [(String, TLAValue)] = [],
  recursiveFunctions: [RecursiveFunc] = [],
  formalOperators: [FormalOperatorDefinition] = []
) throws -> TLAValue {
  let variables = values.sorted { $0.0 < $1.0 }.map { name, value in
    NamedVar(name: name, initial: value)
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

func projection(_ values: [(String, TLAValue)]) throws -> TLAStateProjection {
  try .init(validating: try values.map { name, value in
    .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
  })
}

func value(_ name: String, in projection: TLAStateProjection) throws -> TLAValue? {
  try projection.value(for: #require(TLAStateProjection.Token(validating: name)))
}

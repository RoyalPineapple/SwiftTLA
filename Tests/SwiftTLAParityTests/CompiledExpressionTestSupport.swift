@testable import SwiftTLA
import Testing

func compiledValue(
  _ expression: StateExpr,
  values: [(String, TLAValue)] = [],
  recursiveFunctions: [RecursiveFunc] = [],
  formalOperators: [FormalOperatorDefinition] = []
) throws -> TLAValue {
  let variables = values.sorted { $0.0 < $1.0 }.map { name, value in
    NamedVar(
      name: name,
      initialization: .value(value),
      origin: .compiler
    )
  }
  let resultName = "result"
  let specification = TLASpec(
    name: "CompiledExpressionTest",
    variables: variables + [NamedVar(
      name: resultName,
      initialization: .expression(expression),
      origin: .compiler
    )],
    actions: [],
    invariants: [],
    recursiveFuncs: recursiveFunctions,
    formalOperatorDefinitions: formalOperators
  )
  let compilation = try specification.compile()
  let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
  let result = try #require(compilation.layout.variableID(named: resultName))
  return try initial.value(for: result).rendered(using: compilation.layout)
}

func projection(_ values: [(String, TLAValue)]) throws -> TLAStateProjection {
  try .init(validating: try values.map { name, value in
    .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
  })
}

func value(_ name: String, in projection: TLAStateProjection) throws -> TLAValue? {
  try projection.value(for: #require(TLAStateProjection.Token(validating: name)))
}

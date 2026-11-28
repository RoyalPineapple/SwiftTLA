@testable import SwiftTLA
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

// Retained visitors use unshadowed standard scalars; expand only that notation.
func nativeWitnessSource(_ source: String) -> String {
  Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map { token in
    let type: String
    switch token.tokenKind {
    case .identifier("Int"): type = nativeIntType
    case .identifier("Bool"): type = nativeBoolType
    case .identifier("String"): type = nativeStringType
    default: return token.description
    }
    return "\(token.leadingTrivia)\(type)\(token.trailingTrivia)"
  }.joined()
}

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
  let initial = try firstCompiledState(in: compilation)
  return try renderedValue(named: resultName, in: initial, compilation: compilation)
}

func projection(_ values: [(String, TLAValue)]) throws -> TLAStateProjection {
  try .init(validating: try values.map { name, value in
    .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
  })
}

func value(_ name: String, in projection: TLAStateProjection) throws -> TLAValue? {
  try projection.value(for: #require(TLAStateProjection.Token(validating: name)))
}

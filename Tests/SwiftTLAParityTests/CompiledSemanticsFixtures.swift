@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

func compiledActionProjections(
  _ body: ActionExpr,
  from values: [(String, TLAValue)],
  variables: [String]
) throws -> [TLAStateProjection] {
  let spec = TLASpec(
    name: "ActionFixture",
    variables: variables.map { NamedVar(name: $0, initial: .int(0)) },
    actions: [NamedAction(name: "step", body: body)],
    invariants: []
  )
  let compilation = try spec.compile()
  let compiledValues = try variables.map { variable in
    CompiledValue(formal: try #require(values.first { $0.0 == variable }?.1))
  }
  let state = try CompiledState(values: compiledValues, layout: compilation.layout, identity: compilation.identity)
  let action = try #require(compilation.semantics.behavior.actions.first)
  return try CompiledRuntime(compilation: compilation)
    .successors(for: action.id, from: state)
    .map { try $0.state.projection(using: compilation.layout) }
}

func compiledInitialProjections(_ spec: TLASpec) throws -> [TLAStateProjection] {
  let compilation = try spec.compile()
  return try CompiledRuntime(compilation: compilation).initialStates()
    .map { try $0.projection(using: compilation.layout) }
}

func renderedStateExpression(
  _ expression: StateExpr,
  variables: [String] = ["x", "a", "b", "s"]
) throws -> String {
  try TLASpec(
    name: "StateExpressionRendering",
    variables: variables.map { NamedVar(name: $0, initial: .int(0)) },
    actions: [NamedAction(name: "Tick", body: .guard_(.bool(true)))],
    invariants: [NamedInvariant(name: "Rendered", body: expression)]
  ).compile().render().tlaBundle.tla
}

func renderedActionExpression(_ expression: ActionExpr) throws -> String {
  try TLASpec(
    name: "ActionExpressionRendering",
    variables: [NamedVar(name: "x", initial: .int(0))],
    actions: [NamedAction(name: "Rendered", body: expression)],
    invariants: []
  ).compile().render().tlaBundle.tla
}

enum PartialFunctionKey: Int, CaseIterable, FiniteTLAValueDomain {
  case one = 1

  static let finiteValues: [Self] = [.one]
  static var defaultValue: Self { .one }
}

enum FunctionVariableKey: Int, CaseIterable, FiniteTLAValueDomain {
  case one = 1
  case two = 2

  static var finiteValues: [Self] { allCases }
  static var defaultValue: Self { .one }
}

import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

enum FunctionProcess: String, CaseIterable, FiniteTLAValueDomain {
  case first
  case second

  static let finiteValues = allCases
  static let defaultValue = FunctionProcess.first
}

enum FunctionPhase: String, CaseIterable, FiniteTLAValueDomain {
  case initial
  case done

  static let finiteValues = allCases
  static let defaultValue = FunctionPhase.initial
}

func compiledSuccessors(
  for action: ActionExpr,
  from values: [(String, TLAValue)]
) throws -> (CompiledSpecification, [CompiledState]) {
  let spec = TLASpec(
    name: "ActionExpressionFixture",
    variables: values.sorted { $0.0 < $1.0 }.map { NamedVar(name: $0.0, initial: $0.1) },
    actions: [NamedAction(name: "step", body: action)],
    invariants: []
  )
  let compilation = try spec.compile()
  let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
  let step = try #require(compilation.layout.testActionID(named: "step"))
  let states = try CompiledRuntime(compilation: compilation).successors(for: step, from: initial).map(\.state)
  return (compilation, states)
}

func compiledStateValue(
  named name: String,
  in state: CompiledState,
  compilation: CompiledSpecification
) throws -> TLAValue {
  let variable = try #require(compilation.layout.testVariableID(named: name))
  return try state.value(for: variable).rendered(using: compilation.layout)
}

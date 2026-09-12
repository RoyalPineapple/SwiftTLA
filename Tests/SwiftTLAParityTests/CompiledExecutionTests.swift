import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct CompiledExecutionTests {
  private func successor(
    _ compilation: CompiledSpecification,
    named name: String,
    arguments: [TLAValue] = [],
    from state: CompiledState
  ) throws -> CompiledState {
    let action = try #require(compilation.layout.testActionID(named: name))
    return try #require(try CompiledRuntime(compilation: compilation)
      .successors(for: action, from: state)
      .first { successor in
        try successor.arguments.map { try $0.rendered(using: compilation.layout) } == arguments
      }?.state)
  }

  private func successors(
    _ compilation: CompiledSpecification,
    from state: CompiledState
  ) throws -> [(action: String, arguments: [TLAValue], state: TLAStateProjection)] {
    return try CompiledRuntime(compilation: compilation)
      .successors(from: state)
      .map { successor in
        (
          action: compilation.layout.actions[successor.action.ordinal].declaration.name,
          arguments: try successor.arguments.map { try $0.rendered(using: compilation.layout) },
          state: try successor.state.projection(using: compilation.layout)
        )
      }
  }

  private func compiledStateValue(
    _ name: String,
    in state: CompiledState,
    compilation: CompiledSpecification
  ) throws -> TLAValue {
    let variable = try #require(compilation.layout.testVariableID(named: name))
    return try state.value(for: variable).rendered(using: compilation.layout)
  }

  @Test("compiled execution applies an action")
  func applyAction() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("IncrementingCounter") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let next = try successor(compilation, named: "increment", from: state)
    #expect(try compiledStateValue("count", in: next, compilation: compilation) == .int(2))
  }

  @Test("compiled execution checks invariants")
  func checkInvariant() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("PositiveCounter") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
      Invariant("Positive") { count > 0 }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let invariant = try #require(compilation.semantics.behavior.invariants.first)
    #expect(try CompiledRuntime(compilation: compilation).invariantHolds(invariant, in: state))
  }

  @Test("compiled execution lists available actions")
  func availableActions() throws {
    let count = Var<Int>("count")
    let spec = TLASpec("AvailableAction") {
      Variable(count, 1)
      Action("increment") { count.becomes(count + 1).when(count < 12) }
    }
    let compilation = try spec.compile()
    let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let available = try successors(compilation, from: state).map(\.action)
    #expect(available.contains("increment"))
  }

  @Test("compiled successor relation matches checked transitions from every reachable state")
  func runtimeSuccessorsMatchCheckedTransitions() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("ConstrainedParameterizedCounter") {
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step)
      }
      Constraint(counter <= 2)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(
      compilation: compilation,
      configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
    ).explore()
    let graph = exploration.graph

    for sourceID in graph.states.keys {
      let checked = try (graph.transitions[sourceID] ?? []).compactMap { transition -> (action: String, arguments: [TLAValue], state: TLAStateProjection)? in
        guard let successor = graph.states[transition.target] else { return nil }
        return (
          transition.label.action,
          try transition.label.formalArguments(using: compilation.layout),
          successor
        )
      }
      let runtimeState = try #require(exploration.compiledStates[sourceID])
      let runtimeSuccessors = try successors(compilation, from: runtimeState)

      #expect(multiset(runtimeSuccessors) == multiset(checked))
    }
  }

  private func multiset(
    _ transitions: [(action: String, arguments: [TLAValue], state: TLAStateProjection)]
  ) -> [String: Int] {
    Dictionary(
      transitions.map { ("\($0.action):\($0.arguments) -> \($0.state)", 1) },
      uniquingKeysWith: +
    )
  }

  @Test("compiled execution preserves parameter domains and disabled successors")
  func compiledExecutionPreservesParameterDomainsAndDisabledSuccessors() throws {
    let counter = Var<Int>("counter")
    let step = Var<Int>("step")
    let spec = TLASpec("RuntimeErrors") {
      Variable(counter, 0)
      Action("advance", parameters: [ActionParameter("step", values: [1, 2])]) {
        counter.becomes(counter + step).when(counter == 0)
      }
    }
    let compilation = try spec.compile()
    let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let available: [(action: String, arguments: [TLAValue])] = [
      (action: "advance", arguments: [.int(1)]),
      (action: "advance", arguments: [.int(2)])
    ]

    let discovered = try successors(compilation, from: initial)
    #expect(discovered.count == available.count)
    for (actual, expected) in zip(discovered, available) {
      #expect(actual.action == expected.action)
      #expect(actual.arguments == expected.arguments)
    }

    let advanced = try successor(compilation, named: "advance", arguments: [.int(1)], from: initial)
    let action = try #require(compilation.layout.testActionID(named: "advance"))
    let runtime = CompiledRuntime(compilation: compilation)
    #expect(try runtime.successors(for: action, from: advanced).contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) } == [.int(1)]
    } == false)
    #expect(try runtime.successors(for: action, from: initial).contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) } == [.int(3)]
    } == false)
  }

  @Test("free action reference blocks compilation")
  func freeActionReferenceBlocksCompilation() {
    let counter = Var<Int>("counter")
    let spec = TLASpec("InvalidAvailability") {
      Variable(counter, 0)
      Action("advance") { counter.becomes(counter + 1).when(Expr<Bool>(.variable("missing"))) }
    }
    do {
      _ = try spec.compile()
      Issue.record("Expected a binding diagnostic")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .unknownReference)
      #expect(diagnostic.stage == .binding)
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }

}

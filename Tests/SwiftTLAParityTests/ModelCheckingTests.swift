@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ModelCheckingTests {
  @Test("parameterized actions retain ordered Cartesian invocation labels")
  func parameterizedActionsRetainOrderedCartesianInvocationLabels() throws {
    let value = Var<Int>("value")
    let source = Var<Int>("source")
    let destination = Var<Int>("destination")
    let amount = Var<Int>("amount")
    let spec = TLASpec("ThreeParameterAction") {
      Variable(value, 0)
      Action(
        "transfer",
        parameters: [
          ActionParameter("source", values: [1, 2]),
          ActionParameter("destination", values: [10, 20]),
          ActionParameter("amount", values: [100, 200])
        ]
      ) {
        value.becomes(source + destination + amount)
      }
    }

    #expect(spec.actions[0].bindings.map(\.name) == ["source", "destination", "amount"])
    let compilation = try spec.compile()
    let graph = try ModelChecker(compilation: compilation, configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).exploreGraph()
    let labels = try #require(graph.transitions[.init(0)]).map(\.label)
    let expectedArguments: [[TLAValue]] = [
      [.int(1), .int(10), .int(100)], [.int(1), .int(10), .int(200)],
      [.int(1), .int(20), .int(100)], [.int(1), .int(20), .int(200)],
      [.int(2), .int(10), .int(100)], [.int(2), .int(10), .int(200)],
      [.int(2), .int(20), .int(100)], [.int(2), .int(20), .int(200)]
    ]
    #expect(try labels.map { try $0.formalArguments(using: compilation.layout) } == expectedArguments)
    #expect(try spec.compile().render().tlaBundle.tla.contains("transfer__0_0_0 == transfer(1, 10, 100)"))
    #expect(try spec.compile().render().tlaBundle.tla.contains("transfer__1_1_1 == transfer(2, 20, 200)"))

    let action = try #require(compilation.layout.testActionID(named: "transfer"))
    let runtime = CompiledRuntime(compilation: compilation)
    let initial = try #require(try runtime.initialStates().first)
    let successors = try runtime.successors(for: action, from: initial)
    let next = try #require(successors.first { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) }
        == [.int(2), .int(20), .int(200)]
    })
    let valueID = try #require(compilation.layout.testVariableID(named: "value"))
    #expect(try next.state.value(for: valueID).rendered(using: compilation.layout) == .int(222))
    #expect(try successors.contains { successor in
      try successor.arguments.map { try $0.rendered(using: compilation.layout) }
        == [.int(3), .int(20), .int(200)]
    } == false)
    #expect(try initial.value(for: valueID).rendered(using: compilation.layout) == .int(0))
  }

  @Test func parameterizedActionExpandsFiniteDomainAndLabelsTransitions() throws {
    let value = Var<Int>("value")
    let choice = Var<Int>("choice")
    let spec = TLASpec("ParameterizedAction") {
      Variable(value, 0)
      Action("select", parameters: [ActionParameter("choice", values: [1, 2])]) {
        value.becomes(choice)
      }
    }

    #expect(spec.actions[0].bindings.map(\.name) == ["choice"])
    #expect(spec.actions[0].bindings[0].literalMembers == [.int(1), .int(2)])
    let compilation = try spec.compile()
    let graph = try ModelChecker(compilation: compilation, configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).exploreGraph()
    let transitions = try #require(graph.transitions[.init(0)])
    let labels = transitions.map(\.label)
    #expect(labels.map(\.action) == ["select", "select"])
    #expect(try labels.map { try $0.formalArguments(using: compilation.layout) } == [[.int(1)], [.int(2)]])
    #expect(
      Set(transitions.map(\.action)) == ["select(1)", "select(2)"])
    #expect(try spec.compile().render().tlaBundle.tla.contains("select(choice) =="))
    #expect(try spec.compile().render().tlaBundle.tla.contains("select__0 == select(1)"))
  }

  @Test func explorationResultMatchesExistingCheckerViews() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("ExplorationSnapshot") {
      Variable(x, in: Expr<SetExpr<Int>>(StateExpr.set([1, 2])))
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let checker = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled))

    let exploration = try checker.explore()
    let graph = try checker.exploreGraph()
    let outcome = try checker.check()

    #expect(exploration.initialStateIDs.map(\.id) == [0, 1])
    #expect(exploration.initialStateIDs.allSatisfy { exploration.graph.states[$0] != nil })
    #expect(exploration.graph.states == graph.states)
    #expect(
      exploration.graph.transitions.mapValues { $0.map { "\($0.action):\($0.target.id)" } }
        == graph.transitions.mapValues { $0.map { "\($0.action):\($0.target.id)" } }
    )
    #expect(exploration.outcome.description == outcome.description)
    #expect(exploration.isComplete)

    let incomplete = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1, symmetryReduction: .disabled)).explore()
    #expect(!incomplete.isComplete)
  }

  @Test func twoVarBranching() throws {
    let a = Var<Int>("a")
    let b = Var<Int>("b")
    let spec = TLASpec("Test") {
      Variable(a, 0)
      Variable(b, 0)
      Action("incA") { a.becomes(a + 1).when(a < 2) }
      Action("incB") { b.becomes(b + 1).when(b < 2) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 9)
  }

  @Test func expressionBackedNondeterministicInit() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("LazyInit") {
      Variable(x, in: Expr<SetExpr<Int>>(StateExpr.set([1, 2, 3])))
      Invariant("TypeOK") { x >= 1 && x <= 3 }
    }

    let compilation = try spec.compile()
    let variable = try #require(compilation.layout.testVariableID(named: "x"))
    let initialValues = try CompiledRuntime(compilation: compilation).initialStates().map {
      try $0.value(for: variable).rendered(using: compilation.layout)
    }
    let expectedValues: Set<TLAValue> = [.int(1), .int(2), .int(3)]
    #expect(Set(initialValues) == expectedValues)
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).exploreGraph().states.count == 3)
    #expect(try spec.compile().render().tlaBundle.tla.contains("Init == x \\in {1, 2, 3}"))
  }

}

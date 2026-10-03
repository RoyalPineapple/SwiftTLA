@testable import SwiftTLAPlugin
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ModelCheckingTests {
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

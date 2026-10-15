import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ActionBranchEvaluationTests {
    @Test("A conjunction evaluates its right expression for each left branch")
    func evaluatesEachBranch() throws {
        let spec = canonicalTestSpec(
            variables: [("branch", .value(.int(0))), ("sample", .value(.int(0)))],
            actions: [("advance", .guard_(.value(.bool(true))), [])])
        let compilation = try spec.compile()
        let state = try CompiledState(
            values: [.integer(0), .integer(0)],
            layout: compilation.layout, identity: compilation.identity)
        let branch = try #require(compilation.layout.testVariableID(named: "branch"))
        let sample = try #require(compilation.layout.testVariableID(named: "sample"))
        let first = CompiledExpression(operation: .value(.integer(1)), resultType: .int, children: [])
        let second = CompiledExpression(operation: .value(.integer(2)), resultType: .int, children: [])
        let sampled = CompiledExpression(operation: .value(.integer(99)), resultType: .int, children: [])
        let action = CompiledAction(
            id: try #require(compilation.semantics.behavior.actions.first).id,
            bindings: [],
            body: .and(.or(.assign(branch, first), .assign(branch, second)),
                .assign(sample, sampled)))
        var evaluations = 0
        let enumerator = CompiledActionEnumerator(state: state) { expression, bindings in
            if expression == sampled {
                evaluations += 1
                return .integer(evaluations)
            }
            return try CompiledEvaluator(state: state, operators: compilation.semantics.operators,
                bindings: bindings).evaluate(expression)
        }

        let successors = try enumerator.enumerateSuccessors(action)
        #expect(evaluations == 2)
        #expect(try successors.map { try $0.state.value(for: branch) } == [.integer(1), .integer(2)])
        #expect(try successors.map { try $0.state.value(for: sample) } == [.integer(1), .integer(2)])
    }
}

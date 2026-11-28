import Testing
@testable import SwiftTLA

struct QuantifiedDictionaryReadTests {
    @Test func repeatedReadsRespectTheKeyAndFirstReachedFailure() throws {
        let compiled = try QuantifiedDictionaryReadModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compiled)
        let state = try #require(try runtime.initialStates().first)
        func holds(_ name: String) throws -> Bool {
            let predicate = try #require(compiled.semantics.behavior.invariants.first { $0.name == name })
            return try runtime.invariantHolds(predicate, in: state)
        }
        #expect(try holds("guarded"))
        #expect(try holds("cells"))
        #expect(throws: EvalError.divisionByZero) { try holds("arithmeticFirst") }
        #expect(throws: EvalError.functionArgumentOutsideDomain(.integer(2))) { try holds("lookupFirst") }

        let machine = try QuantifiedDictionaryReadModel.makeMachine()
        #expect(try machine.violatedInvariants(checking: [.guarded, .cells], atLevel: 0).isEmpty)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.violatedInvariants(checking: [.arithmeticFirst], atLevel: 0)
        }
        #expect(throws: NativeMachineEvaluationError.functionArgumentOutsideDomain) {
            try machine.violatedInvariants(checking: [.lookupFirst], atLevel: 0)
        }
    }
}

import Testing
@testable import SwiftTLA
import UpstreamParity

struct KVsnapCorpusExecutionTests {
    @Test("Snapshot-isolation initialization, invariants and choices agree with the formal corpus")
    func nativeSnapshotIsolationRelation() throws {
        let compilation = try KVsnapModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        #expect(initialStates.count == 1)
        let initial = try #require(initialStates.first)
        var native = try KVsnapModel.makeMachine()
        let tx = try #require(compilation.layout.testVariableID(named: "tx"))
        let missed = try #require(compilation.layout.testVariableID(named: "missed"))
        let start = try #require(compilation.layout.testActionID(named: "START"))
        #expect(native.state.tx.isEmpty)
        #expect(Set(native.state.store.keys) == [.k1, .k2])
        #expect(Set(native.state.store.values).count == 1)
        #expect(try initial.value(for: tx) == .set([]))
        let formalMissed = CompiledValue.function(Dictionary(uniqueKeysWithValues:
            native.state.missed.map { transaction, keys in
                (CompiledValue(formal: transaction.tlaValue), .set(Set(keys.map {
                    CompiledValue(formal: $0.tlaValue)
                })))
            }
        ))
        let hasNoMissedVersions = native.state.missed.values.allSatisfy(\.isEmpty)
        #expect(hasNoMissedVersions)
        #expect(try initial.value(for: missed) == formalMissed)
        let violations = try compilation.semantics.behavior.invariants.filter {
            try !runtime.invariantHolds($0, in: initial)
        }.map(\.name)
        #expect(violations.isEmpty)
        #expect(try native.violatedInvariants() == violations)
        #expect(try Set(native.enabledActions()) == [
            .START(process: .t1), .START(process: .t2), .START(process: .t3)
        ])
        let alternatives = try runtime.successors(for: start, from: initial).filter {
            $0.arguments == [CompiledValue(formal: KVsnapModel.Transaction.t1.tlaValue)]
        }
        #expect(Set(alternatives.map(\.state)).count == 9)
        let before = native.state
        do {
            _ = try native.send(.START(process: .t1))
            Issue.record("Distinct read/write key choices must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.state == before)
    }
}

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
        let start = try #require(compilation.layout.testActionID(named: "START"))
        let projection = try native.formalProjection(of: native.snapshot)
        #expect(Set(projection.entries.map { $0.token.description }) == [
            "pc", "store", "tx", "missed", "snapshotStore", "read_keys", "write_keys", "ops"
        ])
        #expect(try projection == initial.projection(using: compilation.layout))
        #expect(native.state.tx.isEmpty)
        #expect(Set(native.state.store.keys) == [.k1, .k2])
        #expect(Set(native.state.store.values).count == 1)
        let hasNoMissedVersions = native.state.missed.values.allSatisfy(\.isEmpty)
        #expect(hasNoMissedVersions)
        let violations = try compilation.semantics.behavior.invariants.filter {
            try !runtime.invariantHolds($0, in: initial)
        }.map(\.name)
        #expect(violations.isEmpty)
        #expect(try native.violatedInvariants().map { KVsnapModel.formalPropertyNames[$0]! } == violations)
        #expect(try Set(native.enabledActions()) == [
            .START(process: .t1), .START(process: .t2), .START(process: .t3)
        ])
        let alternatives = try runtime.successors(for: start, from: initial).filter {
            $0.arguments == [CompiledValue(formal: KVsnapModel.Transaction.t1.tlaValue)]
        }
        #expect(Set(alternatives.map(\.state)).count == 9)
        let nativeAlternatives = try native.successors().filter { $0.action == .START(process: .t1) }
        let nativeStates = try Set(nativeAlternatives.map { try $0.machine.formalProjection(of: $0.machine.snapshot) })
        let formalStates = try Set(alternatives.map { try $0.state.projection(using: compilation.layout) })
        #expect(nativeStates == formalStates)
        let before = native.state
        do {
            _ = try native.send(.START(process: .t1))
            Issue.record("Distinct read/write key choices must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.state == before)
    }
}

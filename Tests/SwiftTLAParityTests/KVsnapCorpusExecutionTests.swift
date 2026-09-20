import Testing
@testable import SwiftTLA
@testable import CanonicalUpstreamCorpus
import UpstreamParity

struct KVsnapCorpusExecutionTests {
    @Test("operation records retain typed transaction and missing-value alternatives")
    func preservesOperationValueTypes() {
        typealias Operation = KVsnapModel.Operation
        let values: [KVsnapModel.Value] = [.first(.t1), .first(.t2), .first(.t3), .second(.noVal)]
        let records = values.map { Operation(op: .write, key: .k2, value: $0) }
        #expect(Set(records).count == values.count)
        for record in records {
            #expect(Operation(formalValue: record.tlaValue) == record)
        }
        #expect(Operation(formalValue: .record(["op": .string("write"), "key": .constant("k2"), "value": .constant("foreign")])) == nil)
        #expect(Operation(formalValue: .record(["op": .string("write"), "key": .constant("k2")])) == nil)
    }

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
        var nativeFrontier = nativeAlternatives.map(\.machine)
        var formalFrontier = alternatives.map(\.state)
        let stages: [(String, KVsnapModel.Action)] = [
            ("READ", .READ(process: .t1)), ("UPDATE", .UPDATE(process: .t1)), ("COMMIT", .COMMIT(process: .t1))
        ]
        for (name, action) in stages {
            let formalAction = try #require(compilation.layout.testActionID(named: name))
            nativeFrontier = try nativeFrontier.flatMap { machine in
                try machine.successors().filter { $0.action == action }.map(\.machine)
            }
            formalFrontier = try formalFrontier.flatMap { state in
                try runtime.successors(for: formalAction, from: state).filter {
                    $0.arguments == [CompiledValue(formal: KVsnapModel.Transaction.t1.tlaValue)]
                }.map(\.state)
            }
            #expect(!nativeFrontier.isEmpty)
            #expect(try Set(nativeFrontier.map { try $0.formalProjection(of: $0.snapshot) })
                == Set(formalFrontier.map { try $0.projection(using: compilation.layout) }))
        }
    }
}

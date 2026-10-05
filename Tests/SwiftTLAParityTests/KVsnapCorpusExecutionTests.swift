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

    @Test("Snapshot-isolation generated initialization and transaction choices remain typed")
    func nativeSnapshotIsolationRelation() throws {
        var native = try KVsnapModel.makeMachine()
        let projection = try native.formalProjection(of: native.snapshot)
        #expect(Set(projection.entries.map { $0.token.description }) == [
            "pc", "store", "tx", "missed", "snapshotStore", "read_keys", "write_keys", "ops"
        ])
        #expect(native.state.tx.isEmpty)
        #expect(Set(native.state.store.keys) == [.k1, .k2])
        #expect(native.state.store.values.allSatisfy { $0 == .second(.noVal) })
        #expect(native.state.missed.values.allSatisfy { $0.isEmpty })
        #expect(try native.violatedInvariants(atLevel: 1).isEmpty)
        #expect(try Set(native.enabledActions()) == [
            .START(process: .t1), .START(process: .t2), .START(process: .t3)
        ])
        let nativeAlternatives = try native.successors().filter { $0.action == .START(process: .t1) }
        #expect(nativeAlternatives.count == 9)
        #expect(Set(nativeAlternatives.map { $0.machine.snapshot }).count == 9)
        #expect(nativeAlternatives.allSatisfy {
            $0.machine.state.tx == [.t1] && $0.machine.state.store == native.state.store
                && $0.machine.state.missed == native.state.missed
        })
        let before = native.state
        do {
            _ = try native.send(.START(process: .t1))
            Issue.record("Distinct read/write key choices must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.state == before)
        var nativeFrontier = nativeAlternatives.map(\.machine)
        let stages: [KVsnapModel.Action] = [
            .READ(process: .t1), .UPDATE(process: .t1), .COMMIT(process: .t1)
        ]
        for action in stages {
            nativeFrontier = try nativeFrontier.flatMap { machine in
                try machine.successors().filter { $0.action == action }.map(\.machine)
            }
            #expect(!nativeFrontier.isEmpty)
            #expect(try nativeFrontier.allSatisfy { try $0.violatedInvariants(atLevel: 1).isEmpty })
            if action == .COMMIT(process: .t1) {
                #expect(nativeFrontier.allSatisfy { $0.state.tx.isEmpty })
                #expect(nativeFrontier.allSatisfy {
                    $0.state.store.values.contains(.first(.t1))
                        && $0.state.store.values.allSatisfy { $0 == .first(.t1) || $0 == .second(.noVal) }
                })
            } else {
                #expect(nativeFrontier.allSatisfy {
                    $0.state.tx == [.t1] && $0.state.store == native.state.store
                })
            }
        }
    }
}

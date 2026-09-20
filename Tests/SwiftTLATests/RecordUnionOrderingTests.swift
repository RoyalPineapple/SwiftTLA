import Testing
@testable import SwiftTLA

struct RecordUnionOrderingTests {
    @Test("same-field record unions retain disjoint value types and native ordering")
    func preservesFieldDomains() throws {
        let values = try RecordUnionFieldDomainModel.initialMachines().map { $0.state.value }
        #expect(values == [.first(.init(value: -1)), .first(.init(value: 0)),
                           .second(.init(value: false)), .second(.init(value: true))])
        for value in values {
            #expect(RecordUnionFieldDomainModel.Value(formalValue: value.tlaValue) == value)
        }
        #expect(RecordUnionFieldDomainModel.Value(formalValue: .record(["value": .string("0")])) == nil)
    }

    @Test("nested record unions use complete structural order in generated native initialization")
    func preservesStructuralOrder() throws {
        let machines = try RecordUnionOrderingModel.initialMachines()
        let values = machines.map { $0.state.value }
        #expect(values.count == 6)
        let formal = values.map { CompiledValue(formal: $0.tlaValue) }
        #expect(formal == formal.sorted())
        #expect(Set(formal).count == 6)
        #expect(values[0] == .first(.init(a: 0, z: 2)))
        #expect(values[1] == .second(.first(.init(a: 1, b: 9))))
        #expect(values[2] == .second(.first(.init(a: 2, b: -1))))
        #expect(values[3] == .first(.init(a: 2, z: 0)))
        #expect(values[4] == .second(.second(.init(a: [], c: false))))
        #expect(values[5] == .second(.second(.init(a: [1], c: true))))
        for var machine in machines {
            let before = machine.state.value
            #expect(RecordUnionOrderingModel.Value(formalValue: before.tlaValue) == before)
            let transition = try machine.send(.finish)
            #expect(transition.after.value == before)
        }
    }

    @Test("record union boundaries reject unknown and malformed record shapes")
    func rejectsMalformedRecords() {
        typealias Value = RecordUnionOrderingModel.Value
        #expect(Value(formalValue: .record(["a": .int(1)])) == nil)
        #expect(Value(formalValue: .record(["a": .int(1), "z": .int(2), "b": .int(3)])) == nil)
        #expect(Value(formalValue: .record(["a": .bool(true), "z": .int(2)])) == nil)
        #expect(Value(formalValue: .record(["a": .tuple([]), "c": .int(1)])) == nil)
    }
}

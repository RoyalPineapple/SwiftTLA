import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct RecordUnionOrderingTests {
    @Test("guarded record union views support symbolic updates and sentinel transitions")
    func updatesSentinelUnion() throws {
        typealias Model = RecordUnionSentinelModel
        var machine = try #require(Model.initialMachines().first { $0.state.value == .second(.noBlock) })
        #expect(try machine.enabledActions() == [.create])
        _ = try machine.send(.create)
        for balance in 1...3 {
            let transition = try machine.send(.advance)
            #expect(transition.after.value == .first(.init(
                block: .init(account: "NoBlock", balance: balance), signature: "NoBlock")))
        }
        #expect(try machine.enabledActions() == [.clear])
        _ = try machine.send(.clear)
        #expect(machine.state.value == .second(.noBlock))
        let graph = try ReachabilityGraph(initialMachines: Model.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == 6)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 9)
    }

    @Test("model-value sentinel unions preserve native identity and reject string substitutes")
    func preservesSentinelIdentity() throws {
        typealias Model = RecordUnionSentinelModel
        let values = try Model.initialMachines().map { $0.state.value }
        #expect(values.count == 3)
        let formal = values.map { CompiledValue(formal: $0.tlaValue) }
        #expect(formal == formal.sorted())
        #expect(values.last == .second(.noBlock))
        #expect(Set(formal).count == 3)
        for value in values {
            #expect(Model.Value(formalValue: value.tlaValue) == value)
        }
        #expect(Model.Value(formalValue: .constant("NoBlock")) == .second(.noBlock))
        #expect(Model.Value(formalValue: .string("NoBlock")) == nil)
        #expect(Model.Value(formalValue: .constant("UnknownBlock")) == nil)
        #expect(Model.Value(formalValue: .record(["type": .string("none")])) == nil)
        #expect(Model.Value(formalValue: .record([
            "block": .record(["account": .string("account"), "balance": .int(3), "extra": .bool(true)]),
            "signature": .string("signature")
        ])) == nil)
    }

    @Test("mixed record domains render as equivalent initial alternatives")
    func rendersMixedRecordDomainWithoutTLCSetOrdering() throws {
        let tla = try RecordUnionFieldDomainModel.spec.compile().render().tlaBundle.tla
        #expect(tla.contains("value = [value |-> -1]"))
        #expect(tla.contains("value = [value |-> 0]"))
        #expect(tla.contains("value = [value |-> FALSE]"))
        #expect(tla.contains("value = [value |-> TRUE]"))
        #expect(tla.contains("value \\in {[value |->") == false)
    }

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

    @Test("five signed-block record shapes and model-value sentinel retain exact values")
    func preservesSignedBlockAlternatives() throws {
        typealias Model = SignedBlockAlternativesModel
        let machines = try Model.initialMachines()
        let values = machines.map(\.state.value)
        #expect(values.count == 6)
        #expect(Set(values).count == 6)
        let formal = values.map { CompiledValue(formal: $0.tlaValue) }
        #expect(formal == formal.sorted())
        for var machine in machines {
            let before = machine.state.value
            #expect(Model.Value(formalValue: before.tlaValue) == before)
            #expect(try machine.send(.finish).after.value == before)
        }
        #expect(Model.Value(formalValue: .record(["block": .record(["type": .string("genesis")])])) == nil)
    }
}

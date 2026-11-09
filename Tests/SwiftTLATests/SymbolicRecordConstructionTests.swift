import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SymbolicRecordConstructionTests {
    @Test("Action arguments construct and update ordinary Swift record fields")
    func executesRecordActionArguments() throws {
        for input in [1, 2] {
            let argument = RecordActionParameterModel.Packet(count: input, ready: false)
            var constructed = try RecordActionParameterModel.makeMachine()
            let construction = try constructed.send(.construct(input: argument))
            #expect(construction.after.packet.count == input && !construction.after.packet.ready)
            #expect(try constructed.formalCall(for: construction.action).arguments ==
                [.record(["count": .int(input), "ready": .bool(false)])])

            var updated = try RecordActionParameterModel.makeMachine()
            let update = try updated.send(.update(input: argument))
            #expect(update.after.packet.count == input && !update.after.packet.ready)
            #expect(try updated.formalCall(for: update.action).arguments ==
                [.record(["count": .int(input), "ready": .bool(false)])])
        }

        let machine = try RecordActionParameterModel.makeMachine()
        let first = RecordActionParameterModel.Action.construct(input: .init(count: 1, ready: false))
        let same = RecordActionParameterModel.Action.construct(input: .init(count: 1, ready: false))
        let second = RecordActionParameterModel.Action.construct(input: .init(count: 2, ready: false))
        let update = RecordActionParameterModel.Action.update(input: .init(count: 1, ready: false))
        let firstCall = try machine.formalCall(for: first)
        let secondCall = try machine.formalCall(for: second)
        let updateCall = try machine.formalCall(for: update)
        #expect(firstCall.arguments == [.record(["count": .int(1), "ready": .bool(false)])])
        #expect(secondCall.arguments == [.record(["count": .int(2), "ready": .bool(false)])])
        #expect(firstCall.name == secondCall.name && firstCall.name != updateCall.name)
        #expect(first == same)
        #expect(first != second)
        #expect(first != update)
        #expect(Set([first, same, second, update]).count == 3)
        var cachedCalls: [RecordActionParameterModel.Action: FormalActionCall] = [:]
        cachedCalls[first] = firstCall
        cachedCalls[second] = secondCall
        cachedCalls[update] = updateCall
        #expect(cachedCalls.count == 3)
        #expect(cachedCalls[first] == firstCall)
        #expect(cachedCalls[second] == secondCall)
        #expect(cachedCalls[update] == updateCall)
    }

    @Test("Symbolic record constructors preserve nested Swift values and parameter bindings")
    func executesTypedRecords() throws {
        let scenario = try #require(try SymbolicRecordConstructionModel.validationScenarios().first)
        var machine = try #require(try scenario.initialMachines().first)
        #expect(machine.state.packet.payload.value == 2 && !machine.state.packet.ready)
        let first = try machine.send(.advance)
        #expect(first.after.packet.payload.value == 3 && first.after.packet.ready)
        let second = try machine.send(.advance)
        #expect(second.after.packet.payload.value == 4 && second.after.packet.ready)
        #expect(try !machine.isEnabled(.advance))
        let graph = try scenario.explore(maximumStates: 10)
        #expect(graph.transitions.count == 3)
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.tla.contains("payload |->"))
        #expect(bundle.tla.contains("ready |->"))
    }

    @Test("Symbolic construction keeps typed expressions until the formal boundary")
    func retainsSourceExpressions() {
        let value = SymbolicRecordConstructionModel.Payload.expression(value: Expr<Int>(.variable("count")))
        let packet: Expr<SymbolicRecordConstructionModel.Packet> =
            SymbolicRecordConstructionModel.Packet.expression(payload: value, ready: true)
        #expect(packet.stateExpr == .recordLiteral(.init(orderedFields: [
            .init(name: "payload", value: .recordLiteral(.init(orderedFields: [
                .init(name: "value", value: .variable("count"))
            ]))),
            .init(name: "ready", value: .bool(true))
        ])))
    }

    @Test("Symbolic constructors retain the same resolved nominal type as concrete constructors")
    func preservesNominalIdentity() throws {
        let model = try swiftRecordModel(replacement: "Packet.expression(count: saved.count + 1, ready: true)")
        let variable = try #require(model.program.layout.variables.first { $0.declaration.name == "packet" })
        #expect(model.program.variableTypes[variable.id] == .nominalRecord("RecordMachine.Packet", [
            .init(name: "count", type: .int), .init(name: "ready", type: .bool)
        ]))
    }

    @Test("Symbolic constructors reject invalid identities, fields, and value types", arguments: [
        "Other.expression(count: 1, ready: true)",
        "Packet.expression(count: true, ready: true)",
        "Packet.expression(count: 1)",
        "Packet.expression(count: 1, ready: true, extra: 2)",
        "Packet.expression(count: 1, count: 2, ready: true)"
    ])
    func rejectsInvalidConstruction(_ replacement: String) throws {
        #expect(throws: CompilationDiagnostic.self) { try swiftRecordModel(replacement: replacement) }
    }
}

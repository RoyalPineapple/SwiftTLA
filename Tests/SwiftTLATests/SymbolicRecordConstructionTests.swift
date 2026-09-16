import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SymbolicRecordConstructionTests {
    @Test("Symbolic record constructors preserve nested Swift values and parameter bindings")
    func executesTypedRecords() throws {
        let scenario = try #require(try SymbolicRecordConstructionModel.validationScenarios().first)
        var machine = try #require(try scenario.initialMachines().first)
        #expect(machine.state.packet == .init(payload: .init(value: 2), ready: false))
        #expect(try machine.send(.advance).after.packet == .init(payload: .init(value: 3), ready: true))
        #expect(try machine.send(.advance).after.packet == .init(payload: .init(value: 4), ready: true))
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

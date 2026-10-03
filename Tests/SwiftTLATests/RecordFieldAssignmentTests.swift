import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct RecordFieldAssignmentTests {
    @Test("record field writes reject mismatched value types", arguments: [
        ("packet.count", "true"), ("packet.ready", "1")
    ])
    func rejectsWrongFieldType(_ target: String, _ value: String) throws {
        #expect(throws: CompilationDiagnostic.self) { try swiftRecordModel(target: target, replacement: value) }
    }

    @Test("record field writes reject missing fields and expression-only locations", arguments: [
        "packet.missing", "packet.expr.count"
    ])
    func rejectsNonLocations(_ target: String) throws {
        #expect(throws: SourceParseDiagnostic.self) { try swiftRecordModel(target: target, replacement: "1") }
    }

    @Test("nested record projections use declared Swift field types at the formal boundary")
    func convertsNestedRecord() {
        typealias Envelope = RecordFieldAssignmentModel.Envelope
        let value = Envelope(packet: .init(count: 2, ready: true), untouched: 7)
        #expect(Envelope(formalValue: value.tlaValue) == value)
        #expect(Envelope.defaultValue == .init(packet: .init(count: 0, ready: false), untouched: 0))
        #expect(Envelope.formalValueShape == .record([
            .init(name: "packet", shape: .record([
                .init(name: "count", shape: .integer), .init(name: "ready", shape: .boolean)
            ])),
            .init(name: "untouched", shape: .integer)
        ]))
        #expect(Envelope(formalValue: .record([
            "packet": .record(["count": .bool(true), "ready": .bool(true)]), "untouched": .int(7)
        ])) == nil)
    }

    @Test("nested record writes compose in order without changing saved values or sibling fields")
    func updatesNestedFields() throws {
        var machine = try RecordFieldAssignmentModel.makeMachine()
        let transition = try machine.send(.advance)
        #expect(transition.before.envelope.packet == .init(count: 0, ready: false))
        #expect(transition.after.envelope.packet == .init(count: 2, ready: true))
        #expect(transition.after.envelope.untouched == 7)
        #expect(transition.after.savedCount == 0)

        let graph = try ReachabilityGraph(initialMachines: RecordFieldAssignmentModel.initialMachines(), maximumStates: 2)
        #expect(graph.transitions.count == 2)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.values.flatMap { $0 }.contains { $0.target == machine.snapshot })

        let rendered = try RecordFieldAssignmentModel.render()
        #expect(rendered.tlaBundle.tla.contains("EXCEPT"))
        #expect(try rendered.plusCalBundle().tla.contains("EXCEPT"))
    }
}

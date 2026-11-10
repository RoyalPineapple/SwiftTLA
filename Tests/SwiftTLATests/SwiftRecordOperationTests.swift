import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SwiftRecordOperationTests {
    @Test("record fingerprints preserve literal kinds and nested field types")
    func fingerprintsResolvedFields() throws {
        func expression(element: CompiledValueType) -> StateExpr {
            .recordLiteral(.init(orderedFields: [.init(name: "items", value: .tupleLiteral([]))],
                nativeType: .nominalRecord("Packet", [.init(name: "items", type: .array(element))])))
        }
        let integers = expression(element: .int)
        let booleans = expression(element: .bool)
        #expect(alphaKey(integers) == alphaKey(expression(element: .int)))
        #expect(alphaKey(integers) != alphaKey(booleans))
        func compilation(_ value: StateExpr) throws -> CompiledSpecification {
            try TLASpec(name: "RecordIdentity",
                variables: [NamedVar(name: "packet", initial: .record(["items": .tuple([])]))],
                actions: [NamedAction(name: "replace", body: .assign(.named("packet"), value))],
                invariants: []).compile()
        }
        #expect(try compilation(integers).identity != compilation(booleans).identity)
        let recordValue = TLAValue.record(["WF_payload": .int(1)])
        let functionValue = TLAValue.function([.string("WF_payload"): .int(1)])
        for (left, right) in [(recordValue, functionValue),
                              (.tuple([recordValue]), .tuple([functionValue])),
                              (.bool(true), .constant("TRUE"))] {
            #expect(left != right)
            #expect(alphaKey(StateExpr.value(left)) != alphaKey(.value(right)))
            #expect(try compilation(.value(left)).identity != compilation(.value(right)).identity)
        }
        #expect(alphaKey(expression(element: .nominalRecord("Item", [.init(name: "value", type: .int)])))
            != alphaKey(expression(element: .nominalRecord("Item", [.init(name: "value", type: .bool)]))))
    }

    @Test("Swift constructors retain their nominal type through saved values and both emitters")
    func preservesConstructorIdentity() throws {
        let model = try swiftRecordModel()
        let variable = try #require(model.program.layout.variables.first { $0.declaration.name == "packet" })
        let expected = CompiledValueType.nominalRecord("RecordMachine.Packet", [
            .init(name: "count", type: .int), .init(name: "ready", type: .bool)
        ])
        #expect(model.program.variableTypes[variable.id] == expected)
        var savedReadTypes: [CompiledValueType] = []
        for action in model.program.behavior.actions {
            _ = action.body.map { root in
                var pending = [root]
                while let expression = pending.popLast() {
                    if case .boundValue = expression.operation { savedReadTypes.append(expression.resultType) }
                    pending.append(contentsOf: expression.children)
                }
                return root
            }
        }
        #expect(savedReadTypes.contains(expected))
        var emitter = NativeSwiftEmitter(model: model)
        let swift = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(swift.contains("public let packet: RecordMachine.Packet"))
        #expect(!swift.contains("struct NativeRecord"))
        #expect(!swift.contains(".compile("))
        let formal = try model.program.renderModule()
        #expect(formal.renderedModuleSource.contains("count |->"))
        #expect(formal.renderedModuleSource.contains("ready |->"))
        #expect(!formal.renderedModuleSource.contains("RecordMachine.Packet"))

        typealias Packet = GeneratedSwiftRecord.Packet
        let authored = SetExpr(Packet(count: 1, ready: false), Packet(count: 2, ready: false),
            Packet(count: 1, ready: false))
        #expect(authored.elements.map(\.count).sorted() == [1, 2])
        #expect(try compiledValue(authored.cardinality.stateExpr) == .int(2))
        let selected = Select(from: authored) { $0.count == 2 }
        #expect(try compiledValue(selected.stateExpr) == .record(["count": .int(2), "ready": .bool(false)]))
        for spelling in ["SetExpr<Packet>.literal", "SetExpr<Packet>"] {
            for predicate in ["candidate in candidate.count == 2", "$0.count == 2"] {
                do {
                    let selected = try swiftRecordModel(replacement:
                        "Select(from: \(spelling)(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { \(predicate) }")
                    let variable = try #require(selected.program.layout.variables.first { $0.declaration.name == "packet" })
                    #expect(selected.program.variableTypes[variable.id] == expected)
                    var selectedEmitter = NativeSwiftEmitter(model: selected)
                    #expect(try !selectedEmitter.machineMembers().isEmpty)
                } catch {
                    Issue.record("\(spelling), \(predicate): \(error)")
                }
            }
        }
        #expect(throws: SourceParseDiagnostic.self) {
            try swiftRecordModel(replacement:
                "Select(from: SetExpr<Packet>(Packet.expression(count: packet.count, ready: true))) { candidate in true }")
        }
    }

    @Test("Swift record constructors reject wrong identities, fields, and field types", arguments: [
        "Other(count: 1, ready: true)",
        "Packet(count: true, ready: true)",
        "Packet(count: 1)",
        "Packet(count: 1, ready: true, extra: 2)",
        "Packet(count: 1, count: 2, ready: true)"
    ])
    func rejectsInvalidConstructors(_ replacement: String) throws {
        #expect(throws: CompilationDiagnostic.self) { try swiftRecordModel(replacement: replacement) }
    }

    @Test("checked record updates and reads preserve the original nominal type")
    func preservesUpdates() throws {
        let compilation = try TLASpec("RecordOperations") { Var("value", 0) }.compile()
        let inputs = try SourceTypeResolver().resolve(in: compilation)
        let checker = try CompiledTypeChecker(inputs: inputs)
        let record = CompiledValueType.nominalRecord("Packet", [
            .init(name: "count", type: .int), .init(name: "ready", type: .bool)
        ])
        let constructor = CompiledExpression.recordLiteral([
            .init(name: "count", value: .value(.integer(0))),
            .init(name: "ready", value: .value(.boolean(false)))
        ], type: record)
        let update = CompiledExpression.except(constructor, .value(.string("count")), .value(.integer(1)))
        let checked = try checker.resolutionScope(update, expected: nil)
        #expect(checked.resultType == record)
        #expect(checked.children[0].resultType == record)
        #expect(try checker.type(of: .recordAccess(update, "count")) == .int)
        #expect(try checker.type(of: .recordAccess(update, "ready")) == .bool)
        #expect(throws: CompilationDiagnostic.self) {
            try checker.type(of: .except(constructor, .value(.string("count")), .value(.boolean(true))))
        }
        #expect(throws: CompilationDiagnostic.self) {
            try checker.type(of: .recordAccess(constructor, "missing"))
        }
        #expect(throws: CompilationDiagnostic.self) {
            try checker.type(of: .recordLiteral([
                .init(name: "count", value: .value(.integer(0))),
                .init(name: "ready", value: .value(.boolean(false)))
            ]), expected: record)
        }
    }
}

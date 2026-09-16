import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SwiftRecordOperationTests {
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

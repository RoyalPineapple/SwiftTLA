import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SwiftRecordTypeTests {
    @Test("explicit imported records validate their shape and preserve nominal identity", arguments: [
        "FormalCall(as: Packet.self, \"read\", input, 1)",
        "ModuleCall(as: Packet.self, \"CC\", \"read\", input, 1)"
    ])
    func projectsImportedRecords(_ source: String) throws {
        let metadata = try swiftRecordMetadata("struct Packet { let value: Int }")
        let parser = ParserSession(sourceTypes: metadata)
        let syntax = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        let scope = ParserSession.TypedFacadeScope.empty.extending(
            binding: "input", to: .variable("__importedRecord"), shape: .int)
        let parsed = try #require(parser.decodeTypedFacadeValue(syntax, scope: scope))
        guard case .letValue(let name, .assertView(let call, let shape), .recordLiteral(let record)) = parsed else {
            Issue.record("Expected a checked, single-evaluation record projection")
            return
        }
        #expect(name != "__importedRecord")
        #expect(call.freeVariableNames == ["__importedRecord"])
        #expect(shape == .record([.init(name: "value", shape: .integer)]))
        #expect(record.nativeType == (try SourceTypeResolver(metadata: metadata).resolve("Packet")))
        #expect(record.fields == [.init(name: "value", value: .recordAccess(.variable(name), "value"))])
    }

    @Test("record union fields retain ordered Swift alternatives without anonymous value types")
    func preservesDeclaredUnionFields() throws {
        let resolver = SourceTypeResolver(metadata: try swiftRecordMetadata("""
            struct Packet: Hashable, Sendable { let payload: OneOf<Int, Bool> }
            """))
        let union = CompiledValueType.oneOf(.int, .bool)
        #expect(try resolver.resolve("OneOf<Int, Bool>") == union)
        #expect(try resolver.resolve("Packet") == .nominalRecord("Model.Packet", [.init(name: "payload", type: union)]))
        #expect(union.components == [.int, .bool])
        #expect(union.swiftType == "OneOf<Int, Bool>")
        let declarations = NativeTypeDeclarations(types: [union], literals: [], namedDomains: [:])
        #expect(declarations.unions.isEmpty)
        #expect(declarations.finiteValues.isEmpty)
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("OneOf<Int, Int>") }
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("OneOf<OneOf<Int, Bool>, Int>") }
    }

    @Test("record emission uses the original Swift type and preserves formal field ordering")
    func emitsOriginalRecordType() throws {
        let compilation = try TLASpec("RecordBoundary") { Var("value", 0) }.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "RecordBoundary", program: program))
        let record = CompiledValueType.nominalRecord("Model.Packet", [
            .init(name: "z", type: .int), .init(name: "a", type: .int)
        ])
        let value = CompiledValue(formal: .record(["z": .int(2), "a": .int(1)]))
        #expect(try emitter.swiftType(record) == "Model.Packet")
        #expect(try emitter.literal(value, as: record) == "Model.Packet(z: 2, a: 1)")
        let ordering = try emitter.ordering(record)
        let a = try #require(ordering.range(of: "lhs.`a`"))
        let z = try #require(ordering.range(of: "lhs.`z`"))
        #expect(a.lowerBound < z.lowerBound)
        let projection = try emitter.formalValue("packet", type: record)
        #expect(projection.contains(".init(\"z\", TLAValue.int(packet.`z`))"))
        #expect(projection.contains(".init(\"a\", TLAValue.int(packet.`a`))"))
    }

    @Test("native record literals reject lossy and malformed field projections")
    func rejectsLossyRecordLiterals() throws {
        let compilation = try TLASpec("RecordBoundary") { Var("value", 0) }.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "RecordBoundary", program: program))
        let record = CompiledValueType.nominalRecord("Model.Packet", [.init(name: "value", type: .int)])
        let invalid: [TLAValue] = [
            .record([:]),
            .record(["value": .int(1), "extra": .int(2)]),
            .record(["wrong": .int(1)]),
            .record(["value": .bool(true)]),
            .record(TLARecord([.init("value", .int(1)), .init("value", .int(2))]))
        ]
        for value in invalid {
            let compiled = CompiledValue(formal: value)
            #expect(throws: (any Error).self) { try emitter.literal(compiled, as: record) }
            #expect(throws: (any Error).self) {
                try emitter.literal(.tuple([compiled]), as: .array(record))
            }
        }
        let valid = CompiledValue(formal: .record(["value": .int(1)]))
        #expect(try emitter.literal(valid, as: record) == "Model.Packet(value: 1)")
        #expect(try emitter.literal(.tuple([valid]), as: .array(record)) == "[Model.Packet(value: 1)]")
    }

    @Test("record literal selection cannot erase fields to fit an earlier union alternative")
    func selectsExactRecordLiteralShape() throws {
        let compilation = try TLASpec("RecordBoundary") { Var("value", 0) }.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "RecordBoundary", program: program))
        let small = CompiledValueType.nominalRecord("Model.Small", [.init(name: "value", type: .int)])
        let large = CompiledValueType.nominalRecord("Model.Large", [
            .init(name: "value", type: .int), .init(name: "extra", type: .bool)
        ])
        let value = CompiledValue(formal: .record(["value": .int(1), "extra": .bool(true)]))
        #expect(try emitter.literal(value, as: .oneOf(small, large)) ==
            "(OneOf<Model.Small, Model.Large>.second(Model.Large(value: 1, extra: true)) as OneOf<Model.Small, Model.Large>)")
        #expect(throws: (any Error).self) {
            try emitter.literal(
                CompiledValue(formal: .record(["value": .int(1), "extra": .bool(true), "unknown": .int(3)])),
                as: .oneOf(small, large))
        }
    }

    @Test("Swift records retain declaration identity, field order, and nested collection types")
    func resolvesNominalRecords() throws {
        let resolver = SourceTypeResolver(metadata: try swiftRecordMetadata("""
            struct Item: Hashable, Sendable { let value: Int }
            struct Packet: Hashable, Sendable {
                let sequence: Int
                let items: [Item]
                let recipients: Set<String>
                static let revision: Int = 1
            }
            typealias Message = Packet
            """))
        let item = CompiledValueType.nominalRecord("Model.Item", [.init(name: "value", type: .int)])
        let packet = CompiledValueType.nominalRecord("Model.Packet", [
            .init(name: "sequence", type: .int),
            .init(name: "items", type: .array(item)),
            .init(name: "recipients", type: .set(.string))
        ])
        #expect(try resolver.resolve("Packet") == packet)
        #expect(try resolver.resolve("Model.Packet") == packet)
        #expect(try resolver.resolve("Message") == packet)
        #expect(try resolver.resolve("[String: Message]") == .dictionary(.string, packet))
        #expect(packet.swiftType == "Model.Packet")
        #expect(packet.resolved)
        #expect(try resolver.formalShape(for: "Packet") == .record([
            .init(name: "sequence", shape: .integer),
            .init(name: "items", shape: .sequence(.record([.init(name: "value", shape: .integer)]))),
            .init(name: "recipients", shape: .set(.string))
        ]))
        let declarations = NativeTypeDeclarations(types: [packet], literals: [], namedDomains: [:])
        #expect(declarations.records.isEmpty)
    }

    @Test("equally named record declarations in different models retain distinct identities")
    func retainsEnclosingDeclaration() throws {
        let declaration = "struct Packet { let value: Int }"
        let first = try SourceTypeResolver(metadata: swiftRecordMetadata(declaration, owner: "First")).resolve("Packet")
        let second = try SourceTypeResolver(metadata: swiftRecordMetadata(declaration, owner: "Second")).resolve("Packet")
        #expect(first != second)
        #expect(throws: CompilationDiagnostic.self) { try CompiledValueType.merge(first, second) }
    }

    @Test("identical record fields do not merge distinct Swift declarations or erase nominal identity")
    func rejectsStructuralSubstitution() throws {
        let resolver = SourceTypeResolver(metadata: try swiftRecordMetadata("""
            struct Request { let value: Int }
            struct Reply { let value: Int }
            """))
        let request = try resolver.resolve("Request")
        let reply = try resolver.resolve("Reply")
        let structural = CompiledValueType.record([.init(name: "value", type: .int)])
        let types = try CompiledTypeContext(enums: .init(), formalNames: [:])
        #expect(request != reply)
        #expect(try CompiledValueType.merge(request, request) == request)
        for other in [reply, structural] {
            #expect(throws: CompilationDiagnostic.self) { try CompiledValueType.merge(request, other) }
            #expect(!types.canProjectRead(request, to: other))
            #expect(!types.canProjectRead(other, to: request))
        }
    }

    @Test("record type inference preserves unresolved field paths")
    func preservesUnresolvedFields() throws {
        let pending = CompiledValueType.nominalRecord("Packet", [.init(name: "items", type: .array(.unknown))])
        let resolved = CompiledValueType.nominalRecord("Packet", [.init(name: "items", type: .array(.int))])
        #expect(!pending.resolved)
        #expect(pending.missingTypePaths() == ["value.items.element"])
        #expect(try CompiledValueType.merge(pending, resolved) == resolved)
        #expect(resolved.strictlyContains(.int))
    }

    @Test("unsupported Swift record fields fail instead of guessing a type", arguments: [
        "struct Record { let value = 1 }",
        "struct Record { var value: Int { 1 } }",
        "struct Record { var children: [Record] }",
        "struct Record { let missing: [Missing] }",
        "struct Record { let value: Int; init(value: Int) { self.value = value + 1 } }",
        "struct Record { @Wrapper var value: Int }",
        "struct Record<T> { let value: T }"
    ])
    func rejectsUnsupportedRecords(_ declaration: String) throws {
        let resolver = SourceTypeResolver(metadata: try swiftRecordMetadata(declaration))
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Record") }
    }
}

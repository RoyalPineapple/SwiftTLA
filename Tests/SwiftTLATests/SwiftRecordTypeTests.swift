import Foundation
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SwiftRecordTypeTests {
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
        "struct Record<T> { let value: T }"
    ])
    func rejectsUnsupportedRecords(_ declaration: String) throws {
        let resolver = SourceTypeResolver(metadata: try swiftRecordMetadata(declaration))
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Record") }
    }
}

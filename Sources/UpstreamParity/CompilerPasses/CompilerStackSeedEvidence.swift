import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum CompilerStackSeedEvidence {
    private struct Receipt: Encodable {
        let compilationIdentity: String
        let operationsSHA256: String
        let files: [String: String]
    }

    package static func prepare(authoredSource: String, nativeSource: String, operations: String, to output: URL) throws {
        let rendered = try OrderedIntTraversalPass.render()
        let root = rendered.tlaBundle.root
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              rendered.tlaBundle.imports.isEmpty, root.name == "OrderedIntTraversalPass",
              let configuration = root.cfg else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "generated render")
        }
        try verifyTraversalSeedAppendRuntime(operations)
        let captured = try capturedRender(nativeSource)
        let authored = try authoredExpansion(authoredSource)
        guard captured.binding.authored == authored, captured.binding.formalAction == "expand",
              captured.binding.formalFields == ["pending", "leftChild", "rightChild"] else {
            throw invalid("authored and typed stack expansion identity")
        }
        guard captured.expansion.countFloor == authored.countFloor,
              captured.expansion.lastIndex == authored.lastIndex,
              captured.expansion.prefixDrop == authored.prefixDrop,
              captured.expansion.localExpandedPosition == authored.localExpandedPosition,
              captured.expansion.pushes.count == authored.pushes.count,
              zip(captured.expansion.pushes, authored.pushes).allSatisfy({ native, source in
                  native.source.utf8.elementsEqual(source.source.utf8)
                      && native.position == source.position && native.expanded == source.expanded
              }) else {
            throw invalid("authored and native stack expansion operands")
        }
        guard captured.module == root.name, captured.identity == identity.value,
              captured.tla.utf8.elementsEqual(root.tla.utf8) else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render bytes")
        }
        let files = [
            root.name + ".tla": Data(root.tla.utf8),
            root.name + ".cfg": Data(configuration.utf8),
            "OrderedIntTraversalPassSource.tla": Data(sourceProof(authored, binding: captured.binding,
                nativeExpansion: captured.expansion, nativeInitialization: captured.initialization).utf8),
        ]
        let hashes = files.mapValues(SHA256.hex)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        for (name, contents) in files {
            try contents.write(to: output.appendingPathComponent(name), options: .atomic)
        }
        try encoder.encode(Receipt(compilationIdentity: identity.value,
                                   operationsSHA256: SHA256.hex(Data(operations.utf8)), files: hashes))
            .write(to: output.appendingPathComponent("files.json"), options: .atomic)
    }

    private static func capturedRender(_ nativeSource: String)
        throws -> (module: String, identity: String, tla: String, binding: OrderedIntStackSeedSource,
                   expansion: NativeTraversalSeedExpansion, initialization: NativeTraversalSeedInitialization) {
        let expansion = Parser.parse(source: nativeSource)
        let renders = expansion.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "render" && $0.modifiers.contains(where: { $0.name.text == "static" }) }
        guard !expansion.hasError, renders.count == 1, let render = renders.first else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render method")
        }
        let declarations = expansion.statements.compactMap { $0.item.as(DeclSyntax.self) }
        let action = try decodeGeneratedTraversalSeedOutput(declarations)
        let initialization = try decodeGeneratedTraversalSeedInitialization(declarations)
        let marker = "// SwiftTLA.OrderedIntStackSeedSource.v1 "
        let receipts = render.leadingTrivia.compactMap { piece -> Data? in
            guard case .lineComment(let comment) = piece, comment.hasPrefix(marker) else { return nil }
            return Data(base64Encoded: String(comment.dropFirst(marker.count)))
        }
        guard receipts.count == 1, let receipt = receipts.first else { throw invalid("typed stack binding receipt") }
        let binding = try JSONDecoder().decode(OrderedIntStackSeedSource.self, from: receipt)
        let initializers = render.body?.statements.compactMap { statement -> FunctionCallExprSyntax? in
            guard let declaration = statement.item.as(VariableDeclSyntax.self), declaration.bindings.count == 1,
                  let binding = declaration.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "_rendered",
                  let call = binding.initializer?.value.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "RenderedSpecification"
            else { return nil }
            return call
        }
        guard let initializers, initializers.count == 1, let arguments = initializers.first?.arguments else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render arguments")
        }
        func literal(_ label: String) -> String? {
            let matches = arguments.filter { $0.label?.text == label }
            guard matches.count == 1 else { return nil }
            return matches.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
        guard let module = literal("_generatedModule"), let identity = literal("compilationIdentity"),
              let source = literal("source") else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render literals")
        }
        return (module, identity, source, binding, action, initialization)
    }

    private static func authoredExpansion(_ source: String) throws -> OrderedIntStackSeedSource.Expansion {
        let file = Parser.parse(source: source)
        let owners = file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { $0.name.text == "OrderedIntTraversalPass" }
        guard !file.hasError, owners.count == 1, let owner = owners.first,
              let model = try ModelSpecificationSyntax.find(in: owner.memberBlock.members, defaultName: owner.name.text),
              model.name == owner.name.text, let result = OrderedIntStackSeedSource.authoredExpansion(model.closure)
        else { throw invalid("authored stack expansion syntax") }
        return result
    }

    private static func invalid(_ field: String) -> EvidenceFormatError {
        .invalidField(record: "OrderedIntTraversalPass", field: field)
    }

    private static func sourceProof(_ authored: OrderedIntStackSeedSource.Expansion,
                                    binding: OrderedIntStackSeedSource,
                                    nativeExpansion: NativeTraversalSeedExpansion,
                                    nativeInitialization: NativeTraversalSeedInitialization) -> String {
        func record(_ fields: [(String, TLAValue)]) -> TLAValue {
            .record(TLARecord(fields.map { .init($0.0, $0.1) }))
        }
        func push(_ source: String, _ position: Int, _ expanded: Bool) -> TLAValue {
            record([("source", .string(source)), ("position", .int(position)), ("expanded", .bool(expanded))])
        }
        func row(_ expansion: OrderedIntStackSeedSource.Expansion) -> TLAValue {
            let pushes = expansion.pushes.map { push($0.source, $0.position, $0.expanded) }
            return record([
                ("label", .string(expansion.label)), ("stack", .string(expansion.stack)),
                ("left", .string(expansion.left)), ("right", .string(expansion.right)),
                ("local", .string(expansion.local)), ("countFloor", .int(expansion.countFloor)),
                ("lastIndex", .string(expansion.lastIndex)), ("prefixDrop", .int(expansion.prefixDrop)),
                ("localExpandedPosition", .int(expansion.localExpandedPosition)), ("write", .string(expansion.write)),
                ("frame", .set(Set(expansion.frame.map(TLAValue.string)))), ("pushes", .tuple(pushes)),
            ])
        }
        func initializerRow(_ left: Int, _ right: Int, elementTypes: [String]) -> TLAValue {
            record([("pending", .tuple([])), ("leftChild", .int(left)), ("rightChild", .int(right)),
                    ("elementTypes", .tuple(elementTypes.map(TLAValue.string)))])
        }
        let native = record([
            ("countFloor", .int(nativeExpansion.countFloor)), ("lastIndex", .string(nativeExpansion.lastIndex)),
            ("prefixDrop", .int(nativeExpansion.prefixDrop)), ("localExpandedPosition", .int(nativeExpansion.localExpandedPosition)),
            ("pushes", .tuple(nativeExpansion.pushes.map { push($0.source, $0.position, $0.expanded) })),
        ])
        let authoredInit = authored.initializers
        let typedInit = binding.typed.initializers
        return #"""
        ---- MODULE OrderedIntTraversalPassSource ----
        EXTENDS Integers, Sequences, TLAPS
        AuthoredStackExpansion == \#(row(authored))
        TypedStackExpansion == \#(row(binding.typed))
        NativeStackReturnedSlots == \#(TLAValue.tuple(nativeExpansion.returnedSlots.map(TLAValue.int)))
        NativeStackExpansion == \#(native)
        TypedStackFormalFields == \#(TLAValue.tuple(binding.formalFields.map(TLAValue.string)))
        TypedStackFieldOrdinals == \#(TLAValue.tuple(binding.fieldOrdinals.map(TLAValue.int)))
        TypedStackActionOrdinal == \#(binding.actionOrdinal)
        TypedStackFormalAction == \#(TLAValue.string(binding.formalAction))
        TypedStackLocalOrdinal == \#(binding.localOrdinal)
        AuthoredStackInitialization == \#(initializerRow(authoredInit.leftChild, authoredInit.rightChild, elementTypes: authoredInit.elementTypes))
        TypedStackInitialization == \#(initializerRow(typedInit.leftChild, typedInit.rightChild, elementTypes: typedInit.elementTypes))
        NativeStackInitialization == \#(initializerRow(nativeInitialization.leftChild, nativeInitialization.rightChild,
            elementTypes: ["Int", "Bool"]))

        THEOREM AuthoredStackExpansionMatchesTypedIR == AuthoredStackExpansion = TypedStackExpansion
        BY ONLY DEF AuthoredStackExpansion, TypedStackExpansion

        THEOREM AuthoredStackInitializationMatchesTypedIR == AuthoredStackInitialization = TypedStackInitialization
        BY ONLY DEF AuthoredStackInitialization, TypedStackInitialization
        ====

        """#
    }
}

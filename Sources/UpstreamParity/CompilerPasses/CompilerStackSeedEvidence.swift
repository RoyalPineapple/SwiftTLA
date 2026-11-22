import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum CompilerStackSeedEvidence {
    private struct Receipt: Encodable {
        let compilationIdentity: String
        let files: [String: String]
    }

    package static func prepare(authoredSource: String, nativeSource: String, to output: URL) throws {
        let rendered = try OrderedIntTraversalPass.render()
        let root = rendered.tlaBundle.root
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              rendered.tlaBundle.imports.isEmpty, root.name == "OrderedIntTraversalPass",
              let configuration = root.cfg else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "generated render")
        }
        let captured = try capturedRender(nativeSource)
        let authored = try authoredExpansion(authoredSource)
        guard captured.binding.authored == authored, captured.binding.formalAction == "expand",
              captured.binding.formalFields == ["pending", "leftChild", "rightChild"] else {
            throw invalid("authored and typed stack expansion identity")
        }
        guard captured.module == root.name, captured.identity == identity.value,
              captured.tla.utf8.elementsEqual(root.tla.utf8) else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render bytes")
        }
        let files = [
            root.name + ".tla": Data(root.tla.utf8),
            root.name + ".cfg": Data(configuration.utf8),
            "OrderedIntTraversalPassSource.tla": Data(sourceProof(authored, binding: captured.binding).utf8),
        ]
        let hashes = files.mapValues(SHA256.hex)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        for (name, contents) in files {
            try contents.write(to: output.appendingPathComponent(name), options: .atomic)
        }
        try encoder.encode(Receipt(compilationIdentity: identity.value, files: hashes))
            .write(to: output.appendingPathComponent("files.json"), options: .atomic)
    }

    private static func capturedRender(_ nativeSource: String)
        throws -> (module: String, identity: String, tla: String, binding: OrderedIntStackSeedSource) {
        let expansion = Parser.parse(source: nativeSource)
        let renders = expansion.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "render" && $0.modifiers.contains(where: { $0.name.text == "static" }) }
        guard !expansion.hasError, renders.count == 1, let render = renders.first else {
            throw EvidenceFormatError.invalidField(record: "OrderedIntTraversalPass", field: "expanded render method")
        }
        try verifyGeneratedTraversalSeedOutput(expansion.statements.compactMap { $0.item.as(DeclSyntax.self) })
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
        return (module, identity, source, binding)
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
                                    binding: OrderedIntStackSeedSource) -> String {
        func record(_ fields: [(String, TLAValue)]) -> TLAValue {
            .record(TLARecord(fields.map { .init($0.0, $0.1) }))
        }
        func row(_ expansion: OrderedIntStackSeedSource.Expansion) -> TLAValue {
            let pushes = expansion.pushes.map {
                record([("source", .string($0.source)), ("position", .int($0.position)), ("expanded", .bool($0.expanded))])
            }
            return record([
                ("label", .string(expansion.label)), ("stack", .string(expansion.stack)),
                ("left", .string(expansion.left)), ("right", .string(expansion.right)),
                ("local", .string(expansion.local)), ("countFloor", .int(expansion.countFloor)),
                ("lastIndex", .string(expansion.lastIndex)), ("prefixDrop", .int(expansion.prefixDrop)),
                ("localExpandedPosition", .int(expansion.localExpandedPosition)), ("write", .string(expansion.write)),
                ("frame", .set(Set(expansion.frame.map(TLAValue.string)))), ("pushes", .tuple(pushes)),
            ])
        }
        return #"""
        ---- MODULE OrderedIntTraversalPassSource ----
        EXTENDS Integers, Sequences, TLAPS
        AuthoredStackExpansion == \#(row(authored))
        TypedStackExpansion == \#(row(binding.typed))
        TypedStackFormalFields == \#(TLAValue.tuple(binding.formalFields.map(TLAValue.string)))
        TypedStackFieldOrdinals == \#(TLAValue.tuple(binding.fieldOrdinals.map(TLAValue.int)))
        TypedStackActionOrdinal == \#(binding.actionOrdinal)
        TypedStackFormalAction == \#(TLAValue.string(binding.formalAction))
        TypedStackLocalOrdinal == \#(binding.localOrdinal)

        THEOREM AuthoredStackExpansionMatchesTypedIR == AuthoredStackExpansion = TypedStackExpansion
        BY ONLY DEF AuthoredStackExpansion, TypedStackExpansion
        ====

        """#
    }
}

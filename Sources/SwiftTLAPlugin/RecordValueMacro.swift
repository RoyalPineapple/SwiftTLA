import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftTLA

public struct RecordValueMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let record = declaration.as(StructDeclSyntax.self) else { return [] }
        let fields = try record.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { !$0.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" } }
            .flatMap { variable in
                try variable.bindings.map { binding -> String in
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                          binding.accessorBlock == nil else {
                        throw CompiledValueType.diagnostic("record", "formal conversion requires resolved stored fields")
                    }
                    return name
                }
            }
        let defaults = fields.map { "\($0): Self._formalRecordDefault(for: \\Self.`\($0)`)" }.joined(separator: ", ")
        let shapes = fields.map { ".init(name: \(String(reflecting: $0)), shape: Self._formalRecordShape(for: \\Self.`\($0)`))" }.joined(separator: ", ")
        let values = fields.map { ".init(\(String(reflecting: $0)), self.`\($0)`.tlaValue)" }.joined(separator: ", ")
        let names = fields.sorted().map { String(reflecting: $0) }.joined(separator: ", ")
        let decoded = fields.enumerated().map { index, field in
            "let raw\(index) = record.value(named: \(String(reflecting: field))), let value\(index) = Self._formalRecordValue(raw\(index), for: \\Self.`\(field)`)"
        }
        let guards = (["case .record(let record) = formalValue", "record.fields.map(\\.name) == [\(names)]"] + decoded).joined(separator: ",\n")
        let arguments = fields.enumerated().map { "\($0.element): value\($0.offset)" }.joined(separator: ", ")
        let fieldNames = fields.map {
            "if keyPath == \\Self.`\($0)` { return \(String(reflecting: $0)) }"
        }.joined(separator: "\n")
        return [try ExtensionDeclSyntax("""
        extension \(type): SwiftTLA._GeneratedRecordValue {
            public static func _formalRecordFieldName(_ keyPath: PartialKeyPath<Self>) -> String? {
                \(raw: fieldNames)
                return nil
            }
            public static var defaultValue: Self { Self(\(raw: defaults)) }
            public static var formalValueShape: SwiftTLA.FormalValueShape { .record([\(raw: shapes)]) }
            public var tlaValue: SwiftTLA.TLAValue { .record(SwiftTLA.TLARecord([\(raw: values)])) }
            public init?(formalValue: SwiftTLA.TLAValue) {
                guard \(raw: guards) else { return nil }
                self.init(\(raw: arguments))
            }
        }
        """)]
    }
}

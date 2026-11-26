import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftTLA

extension StructDeclSyntax {
    var hasTLATupleAttribute: Bool {
        attributes.contains { attribute in
            guard let name = attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription else { return false }
            return name == "TLATuple" || name == "SwiftTLAMacros.TLATuple"
        }
    }
}

public struct TupleValueMacro: ExtensionMacro, MemberMacro {
    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let tuple = declaration.as(StructDeclSyntax.self) else {
            throw CompiledValueType.diagnostic("tuple", "@TLATuple requires a struct")
        }
        let fields = try RecordValueMacro.recordFields(tuple)
        let access = RecordValueMacro.accessPrefix(for: tuple, in: context)
        let parameters = fields.enumerated().map { index, field in
            "`\(field.name)` _field\(index): some SwiftTLA.TypedExpression<\(field.type)>"
        }.joined(separator: ", ")
        let values = fields.indices.map { "_field\($0).stateExpr" }.joined(separator: ", ")
        return [DeclSyntax("""
        \(raw: access)static func expression(\(raw: parameters)) -> SwiftTLA.Expr<Self> {
            SwiftTLA.Expr(.tupleLiteral([\(raw: values)]))
        }
        """)]
    }

    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let tuple = declaration.as(StructDeclSyntax.self) else { return [] }
        let fields = try RecordValueMacro.recordFields(tuple)
        let access = RecordValueMacro.accessPrefix(for: tuple, in: context)
        let defaults = fields.map { "\($0.name): .defaultValue" }.joined(separator: ", ")
        let shapes = fields.map { "Self._tupleFieldType(\\Self.`\($0.name)`).formalValueShape" }.joined(separator: ", ")
        let values = fields.map { "self.`\($0.name)`.tlaValue" }.joined(separator: ", ")
        let issues = (fields.map { "if let issue = self.`\($0.name)`.sourceIssue { return issue }" } + ["return nil"]).joined(separator: "\n")
        let decoded = fields.enumerated().map { i, field in
            "let field\(i) = Self._tupleField(values[\(i)], as: Self._tupleFieldType(\\Self.`\(field.name)`))"
        }
        let guards = (["case .tuple(let values) = formalValue", "values.count == \(fields.count)"] + decoded).joined(separator: ",\n")
        let args = fields.enumerated().map { "\($0.element.name): field\($0.offset)" }.joined(separator: ", ")
        let indices = fields.enumerated().map { i, field in
            "if keyPath == \\Self.`\(field.name)` { return \(i + 1) }"
        }.joined(separator: "\n")
        return [try ExtensionDeclSyntax("""
        extension \(type): SwiftTLA._GeneratedTupleValue {
            \(raw: access)static func _formalTupleIndex(_ keyPath: PartialKeyPath<Self>) -> Int? {
                \(raw: indices)
                return nil
            }
            \(raw: access)static var defaultValue: Self { Self(\(raw: defaults)) }
            \(raw: access)static var formalValueShape: SwiftTLA.FormalValueShape { .tuple([\(raw: shapes)]) }
            \(raw: access)var sourceIssue: SwiftTLA.SourceModelIssue? { \(raw: issues) }
            \(raw: access)var tlaValue: SwiftTLA.TLAValue { .tuple([\(raw: values)]) }
            \(raw: access)init?(formalValue: SwiftTLA.TLAValue) {
                guard \(raw: guards) else { return nil }
                self.init(\(raw: args))
            }
        }
        """)]
    }
}

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGenerator

public struct AttachedTLASpecMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLASpec on structs only")
        }

        let typeName = structDecl.name.text
        var variables: [(name: String, initial: String)] = []
        var actions: [(name: String, varName: String, expr: String, condition: String?)]

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let initial = binding.initializer?.value.description.trimmingCharacters(in: .whitespaces) ?? "0"
                    variables.append((name, initial))
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let actName = funcDecl.name.text
                // Extract .becomes() calls from function body — placeholder for now
            }
        }

        // For now, generate the Action enum + initializer. Full checker integration next.
        let initialArgs = variables.map { "\($0.name): \($0.initial)" }.joined(separator: ", ")

        return [
            DeclSyntax(stringLiteral: """
                static let initial = \(typeName)(\(initialArgs))
                """),
        ]
    }
}

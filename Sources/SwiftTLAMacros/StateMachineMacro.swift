import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StateMachineMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let closure = node.trailingClosure else {
            throw MacroError.message("#StateMachine requires a trailing closure")
        }

        var variables: [(name: String, type: String, initial: String)] = []
        var actions: [(name: String, caseName: String)] = []
        var invariants: [String] = []
        var typeName = "GeneratedStateMachine"

        for item in closure.statements {
            guard let funcCall = item.item.as(FunctionCallExprSyntax.self),
                  let callee = funcCall.calledExpression.as(DeclReferenceExprSyntax.self) else { continue }

            switch callee.baseName.text {
            case "Variable":
                if let args = funcCall.arguments {
                    let parts = args.map { $0.expression.description.trimmingCharacters(in: .whitespaces) }
                    if parts.count >= 2 {
                        let varName = parts[0]
                        let initialVal = parts[1]
                        let type = initialVal.contains("\"") || initialVal.contains("set(") ? "Set<TLAValue>" : "Int"
                        variables.append((varName, type, initialVal))
                    }
                }
            case "Act":
                if let args = funcCall.arguments, let first = args.first {
                    let rawName = first.expression.description
                        .replacingOccurrences(of: "\"", with: "")
                    let caseName = rawName.prefix(1).lowercased() + rawName.dropFirst()
                    actions.append((rawName, caseName))
                }
            case "Inv":
                if let args = funcCall.arguments, let first = args.first {
                    let rawName = first.expression.description.replacingOccurrences(of: "\"", with: "")
                    invariants.append(rawName)
                }
            case "TypeName":
                if let args = funcCall.arguments, let first = args.first {
                    typeName = first.expression.description.replacingOccurrences(of: "\"", with: "")
                }
            default: break
            }
        }

        let structDecl = try generateStruct(name: typeName, variables: variables, actions: actions)
        let actionEnumDecl = try generateActionEnum(name: typeName, actions: actions)

        return [DeclSyntax(structDecl), DeclSyntax(actionEnumDecl)]
    }

    private static func generateStruct(
        name: String,
        variables: [(name: String, type: String, initial: String)],
        actions: [(name: String, caseName: String)]
    ) throws -> StructDeclSyntax {
        let varDecls = variables.map { "var \($0.name): \($0.type)" }
        let initParams = variables.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        let initBody = variables.map { "self.\($0.name) = \($0.name)" }
        let initialValues = variables.map { "\($0.name): \($0.initial)" }.joined(separator: ", ")
        let actionType = "\(name).Action"

        return try StructDeclSyntax(
            name: .identifier(name),
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Equatable"))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Hashable"))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Codable"))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Sendable"))
            }
        ) {
            for v in varDecls { DeclSyntax(stringLiteral: "    \(v)") }
            DeclSyntax(stringLiteral: "")
            try InitializerDeclSyntax("init(\(raw: initParams))") {
                for b in initBody { ExprSyntax(stringLiteral: b) }
            }
            DeclSyntax(stringLiteral: "")
            DeclSyntax(stringLiteral: "    static let initial = \(name)(\(initialValues))")
            DeclSyntax(stringLiteral: "")
            DeclSyntax(stringLiteral: "    var availableActions: [\(actionType)] { [] }")
            DeclSyntax(stringLiteral: "")
            try FunctionDeclSyntax("mutating func apply(_ action: \(raw: actionType))") {
                StmtSyntax(stringLiteral: "fatalError(\"Not implemented — run swift-tla generate for full transition table\")")
            }
        }
    }

    private static func generateActionEnum(
        name: String,
        actions: [(name: String, caseName: String)]
    ) throws -> ExtensionDeclSyntax {
        let actionEnum = "\(name).Action"
        return try ExtensionDeclSyntax(extendedType: IdentifierTypeSyntax(name: .identifier(name))) {
            try EnumDeclSyntax(
                name: .identifier("Action"),
                inheritanceClause: InheritanceClauseSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Identifiable"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Codable"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Sendable"))
                }
            ) {
                for (_, caseName) in actions {
                    "case \(raw: caseName)"
                }
                DeclSyntax(stringLiteral: "")
                DeclSyntax(stringLiteral: "        var id: Self { self }")
            }
        }
    }
}

enum MacroError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        if case .message(let m) = self { return m }
        return "unknown"
    }
}

@main
struct SwiftTLAMacros: CompilerPlugin {
    let providingMacros: [Macro.Type] = [StateMachineMacro.self]
}

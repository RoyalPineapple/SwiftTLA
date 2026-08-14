import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// The freestanding boundary that lets the compiler see an entire formal
/// specification body before its enclosing `@TLAModel` expands. The builder
/// body remains intact so runtime construction stays independent of parsing.
public struct SpecExpressionMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let name = node.arguments.first?.expression.as(StringLiteralExprSyntax.self),
              let closure = node.trailingClosure
        else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: SpecExpressionDiagnostic("#spec requires a string literal name and a builder body")
            ))
            return "TLASpec(\"InvalidSpec\") {}"
        }

        return ExprSyntax(stringLiteral: "TLASpec(\(name.description)) \(closure.description)")
    }
}

private struct SpecExpressionDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-spec-expression")
    let severity: DiagnosticSeverity = .error

    init(_ message: String) {
        self.message = message
    }
}

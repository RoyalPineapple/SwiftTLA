import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

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
                message: SpecExpressionDiagnostic(
                    actual: node.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ))
            return specCall(
                named: StringLiteralExprSyntax(content: "InvalidSpec"),
                body: ClosureExprSyntax(statements: [])
            )
        }

        return specCall(named: name, body: closure)
    }

    private static func specCall(
        named name: some ExprSyntaxProtocol,
        body: ClosureExprSyntax
    ) -> ExprSyntax {
        ExprSyntax(FunctionCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("TLASpec")),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: name)
            ]),
            rightParen: .rightParenToken(),
            trailingClosure: body
        ))
    }
}

private struct SpecExpressionDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-spec-expression")
    let severity: DiagnosticSeverity = .error
    let actual: String

    var message: String {
        "What failed: #spec invocation could not be parsed. Where: this #spec expression. "
            + "Expected: a string literal specification name followed by a builder closure. "
            + "Actual: \(actual). "
            + "Next safe action: write #spec(\"Name\") { ... } and compile again."
    }
}

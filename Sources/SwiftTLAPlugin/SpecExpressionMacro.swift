import Foundation
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
                message: SpecExpressionDiagnostic(
                    actual: node.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ))
            return specCall(
                named: StringLiteralExprSyntax(content: "InvalidSpec"),
                body: ClosureExprSyntax(statements: [])
            )
        }

        let runtimeClosure = SpecDeclarationRegistration().rewrite(Syntax(closure))
            .as(ClosureExprSyntax.self) ?? closure
        return specCall(named: name, body: runtimeClosure)
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

private final class SpecDeclarationRegistration: SyntaxRewriter {
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let rewritten = super.visit(node)
        var items: [CodeBlockItemSyntax] = []
        for item in rewritten {
            items.append(item)
            guard let reference = declaredVariableReference(in: item) else { continue }
            items.append(
                .init(item: .expr(ExprSyntax(reference)))
            )
        }
        return .init(items)
    }

    private func declaredVariableReference(in item: CodeBlockItemSyntax) -> DeclReferenceExprSyntax? {
        guard case .decl(let declaration) = item.item,
              let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              let constructor = initializer.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              constructor == "SharedVar" || constructor == "LocalVar"
        else { return nil }
        return .init(baseName: name)
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

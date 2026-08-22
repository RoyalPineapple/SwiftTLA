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

        let rewriter = BinderLocationRewriter(context: context)
        let rewritten = rewriter.rewrite(closure).as(ClosureExprSyntax.self) ?? closure
        return specCall(named: name, body: rewritten)
    }

    private static func specCall(
        named name: some ExprSyntaxProtocol,
        body: ClosureExprSyntax
    ) -> ExprSyntax {
        let arguments: LabeledExprListSyntax
        if body.signature == nil {
            arguments = [
                LabeledExprSyntax(expression: name, trailingComma: .commaToken()),
                LabeledExprSyntax(expression: ExprSyntax(body))
            ]
            return ExprSyntax(FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("TLASpec")),
                leftParen: .leftParenToken(),
                arguments: arguments,
                rightParen: .rightParenToken()
            ))
        }
        arguments = [
            LabeledExprSyntax(expression: name, trailingComma: .commaToken()),
            LabeledExprSyntax(
                label: .identifier("scoped"),
                colon: .colonToken(),
                expression: ExprSyntax(body)
            )
        ]
        return ExprSyntax(FunctionCallExprSyntax(
            calledExpression: DeclReferenceExprSyntax(baseName: .identifier("TLASpec")),
            leftParen: .leftParenToken(),
            arguments: arguments,
            rightParen: .rightParenToken()
        ))
    }

}

private final class BinderLocationRewriter: SyntaxRewriter {
    private let context: any MacroExpansionContext
    private static let helperNames: Set<String> = [
        "All", "Choose", "Exists", "ForAll", "Let", "LetRec", "With"
    ]

    init(context: some MacroExpansionContext) {
        self.context = context
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node).as(FunctionCallExprSyntax.self) ?? node
        guard let location = context.location(of: node),
              let name = helperName(in: visited),
              Self.helperNames.contains(name),
              visited.arguments.contains(where: { $0.label?.text == "file" }) == false
        else {
            return ExprSyntax(visited)
        }

        var arguments = Array(visited.arguments)
        let insertionIndex = name == "LetRec"
            ? arguments.firstIndex(where: { $0.label?.text == "in" }) ?? arguments.endIndex
            : arguments.endIndex
        arguments.insert(argument("file", location.file), at: insertionIndex)
        arguments.insert(argument("line", location.line), at: insertionIndex + 1)
        arguments.insert(argument("column", location.column), at: insertionIndex + 2)
        for index in arguments.indices {
            arguments[index].trailingComma = index == arguments.indices.last ? nil : .commaToken()
        }

        return ExprSyntax(visited.with(\.arguments, LabeledExprListSyntax(arguments)))
    }

    private func helperName(in call: FunctionCallExprSyntax) -> String? {
        call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? call.calledExpression.as(GenericSpecializationExprSyntax.self)?
                .expression.as(DeclReferenceExprSyntax.self)?.baseName.text
    }

    private func argument(_ label: String, _ expression: ExprSyntax) -> LabeledExprSyntax {
        LabeledExprSyntax(
            label: .identifier(label),
            colon: .colonToken(),
            expression: expression
        )
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

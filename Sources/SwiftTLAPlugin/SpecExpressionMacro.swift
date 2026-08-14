import SwiftDiagnostics
import SwiftParser
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

        let runtimeClosure = DeclarationRegistrationRewriter().rewrite(Syntax(closure))
            .as(ClosureExprSyntax.self) ?? closure
        return ExprSyntax(stringLiteral: "TLASpec(\(name.description)) \(runtimeClosure.description)")
    }
}

/// Result builders intentionally do not receive a `let` declaration as an
/// element. `#spec` adds the declaration handle as the immediately following
/// builder expression. The parser sees the source declaration directly, so
/// the parser and runtime-builder constructions remain independent.
private final class DeclarationRegistrationRewriter: SyntaxRewriter {
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let rewritten = super.visit(node)
        var items: [CodeBlockItemSyntax] = []
        for item in rewritten {
            let declaration = rewriteAlgorithmVariableDeclaration(in: item)
            items.append(declaration.item)
            guard let name = declaration.name else { continue }
            let parsed = Parser.parse(source: name)
            items.append(contentsOf: parsed.statements)
        }
        return CodeBlockItemListSyntax(items)
    }

    private func rewriteAlgorithmVariableDeclaration(
        in item: CodeBlockItemSyntax
    ) -> (item: CodeBlockItemSyntax, name: String?) {
        guard case .decl(let declaration) = item.item,
              let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              let called = initializer.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              called == "SharedVar" || called == "LocalVar" || called == "SharedCollection"
        else { return (item, nil) }

        let hasExplicitName = initializer.arguments.contains {
            $0.label == nil && $0.expression.is(StringLiteralExprSyntax.self)
        }
        guard !hasExplicitName else { return (item, name) }

        var arguments = initializer.arguments
        arguments.insert(
            LabeledExprSyntax(
                expression: StringLiteralExprSyntax(content: name),
                trailingComma: .commaToken()
            ),
            at: arguments.startIndex
        )
        let rewrittenCall = initializer.with(\.arguments, arguments)
        let rewrittenInitializer = binding.initializer!.with(\.value, ExprSyntax(rewrittenCall))
        let rewrittenBinding = binding.with(\.initializer, rewrittenInitializer)
        let rewrittenVariable = variable.with(\.bindings, PatternBindingListSyntax([rewrittenBinding]))
        return (item.with(\.item, .decl(DeclSyntax(rewrittenVariable))), name)
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

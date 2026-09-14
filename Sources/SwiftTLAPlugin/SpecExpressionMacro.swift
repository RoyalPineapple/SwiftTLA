import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
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

        let rewriter = DSLRewriter(context: context)
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

private final class DSLRewriter: SyntaxRewriter {
    private let context: any MacroExpansionContext
    private static let helperNames: Set<String> = [
        "Choose", "Exists", "Fold", "ForAll", "Let", "LetRec", "Select", "Where", "With"
    ]
    private static let stepBuilders: Set<String> = ["Do", "While", "Macro", "If", "Either", "Choose", "With", "Let"]
    private static let memberHelperNames: Set<String> = ["filtering", "forAll", "mapping", "selecting"]

    init(context: some MacroExpansionContext) {
        self.context = context
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        var visited = super.visit(node).as(FunctionCallExprSyntax.self) ?? node
        if let name = helperName(in: node), Self.stepBuilders.contains(name) {
            if let original = node.trailingClosure, let body = visited.trailingClosure {
                visited.trailingClosure = body.with(\.statements,
                    savingBindings(Array(body.statements), original: Array(original.statements)))
            }
            visited.additionalTrailingClosures = MultipleTrailingClosureElementListSyntax(
                zip(node.additionalTrailingClosures, visited.additionalTrailingClosures).map { original, current in
                    var result = current
                    result.closure.statements = savingBindings(Array(current.closure.statements),
                        original: Array(original.closure.statements))
                    return result
                })
        }
        let hasClosure = visited.trailingClosure != nil
            || visited.arguments.contains { $0.expression.is(ClosureExprSyntax.self) }
        guard let location = context.location(of: node),
              let name = helperName(in: visited),
              Self.helperNames.contains(name) || (Self.memberHelperNames.contains(name) && hasClosure),
              visited.arguments.contains(where: { $0.label?.text == "file" }) == false
        else {
            return ExprSyntax(visited)
        }

        var arguments = Array(visited.arguments)
        let insertionIndex = name == "LetRec"
            ? arguments.firstIndex(where: { $0.label?.text == "in" }) ?? arguments.endIndex
            : arguments.firstIndex(where: { $0.expression.is(ClosureExprSyntax.self) }) ?? arguments.endIndex
        arguments.insert(argument("file", location.file), at: insertionIndex)
        arguments.insert(argument("line", location.line), at: insertionIndex + 1)
        arguments.insert(argument("column", location.column), at: insertionIndex + 2)
        for index in arguments.indices {
            arguments[index].trailingComma = index == arguments.indices.last ? nil : .commaToken()
        }

        return ExprSyntax(visited
            .with(\.leftParen, visited.leftParen ?? .leftParenToken())
            .with(\.arguments, LabeledExprListSyntax(arguments))
            .with(\.rightParen, visited.rightParen ?? .rightParenToken()))
    }

    /// Reuses the existing scoped value binding so built specifications and
    /// generated machines give a Swift `let` the same snapshot semantics.
    private func savingBindings(
        _ items: [CodeBlockItemSyntax],
        original sources: [CodeBlockItemSyntax]
    ) -> CodeBlockItemListSyntax {
        guard let index = items.firstIndex(where: { $0.item.as(VariableDeclSyntax.self) != nil }),
              let declaration = items[index].item.as(VariableDeclSyntax.self)
        else { return CodeBlockItemListSyntax(items) }
        guard declaration.bindingSpecifier.text == "let",
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self),
              let initializer = binding.initializer?.value,
              let location = context.location(of: sources[index])
        else {
            context.diagnose(Diagnostic(node: Syntax(sources[index]), message: StepBindingDiagnostic()))
            return CodeBlockItemListSyntax(items)
        }
        let rest = savingBindings(Array(items.dropFirst(index + 1)),
            original: Array(sources.dropFirst(index + 1)))
        var prefix = Array(items.prefix(index))
        let value: ExprSyntax
        if binding.typeAnnotation != nil {
            // Keep Swift's explicit type check on the initializer before binding
            // its value; the closure parameter represents the saved expression.
            let temporary = context.makeUniqueName("savedValue")
            var typedBinding = binding
            typedBinding.pattern = PatternSyntax(IdentifierPatternSyntax(identifier: temporary))
            var typedDeclaration = declaration
            typedDeclaration.bindings = PatternBindingListSyntax([typedBinding])
            prefix.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(typedDeclaration))))
            value = ExprSyntax(DeclReferenceExprSyntax(baseName: temporary))
        } else {
            value = initializer
        }
        let saved: ExprSyntax = """
        Let(\(value), file: \(location.file), line: \(location.line), column: \(location.column)) { \(name) in
            \(rest)
        }
        """
        return CodeBlockItemListSyntax(prefix + [CodeBlockItemSyntax(item: .expr(saved))])
    }

    private func helperName(in call: FunctionCallExprSyntax) -> String? {
        let expression = call.calledExpression.as(GenericSpecializationExprSyntax.self)?.expression
            ?? call.calledExpression
        return expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
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

private struct StepBindingDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-step-binding")
    let severity: DiagnosticSeverity = .error
    let message = "A step binding must be one named let with an initializer. Use Assign to update machine state."
}

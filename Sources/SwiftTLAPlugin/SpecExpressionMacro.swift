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

        let parameterScope: String?
        switch closure.signature?.parameterClause {
        case .simpleInput(let list): parameterScope = list.first?.name.sourceIdentifierName
        case .parameterClause(let clause): parameterScope = clause.parameters.first.map { $0.secondName?.sourceIdentifierName ?? $0.firstName.sourceIdentifierName }
        case nil: parameterScope = nil
        }
        let rewriter = DSLRewriter(context: context, parameterScope: parameterScope)
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
    private let parameterScope: String?
    private static let helperNames: Set<String> = [
        "Choose", "Exists", "Fold", "ForAll", "Let", "LetRec", "Select", "Where", "With"
    ]
    private static let stepBuilders: Set<String> = ["Do", "While", "Macro", "If", "Either", "Choose", "With", "Let"]
    private static let memberHelperNames: Set<String> = ["filtering", "forAll", "mapping", "selecting"]

    init(context: some MacroExpansionContext, parameterScope: String?) {
        self.context = context
        self.parameterScope = parameterScope
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        var visited = super.visit(node).as(VariableDeclSyntax.self) ?? node
        visited.bindings = PatternBindingListSyntax(zip(node.bindings, visited.bindings).map { source, binding in
            var binding = binding
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  var call = binding.initializer?.value.as(FunctionCallExprSyntax.self) else { return binding }
            let member = call.calledExpression.as(MemberAccessExprSyntax.self)
            if let member, ["sharedVar", "localVar"].contains(member.declName.baseName.sourceIdentifierName),
               !call.arguments.contains(where: { $0.label?.text == "_name" }) {
                guard node.bindingSpecifier.text == "let" else {
                    context.diagnose(Diagnostic(node: Syntax(source), message: StateBindingDiagnostic()))
                    return binding
                }
                let argument = LabeledExprSyntax(label: .identifier("_name"), colon: .colonToken(),
                    expression: StringLiteralExprSyntax(content: name), trailingComma: .commaToken())
                call.arguments = LabeledExprListSyntax([argument] + Array(call.arguments))
                binding.initializer?.value = ExprSyntax(call)
                return binding
            }
            let constructor = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName
                ?? (member?.base?.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "SwiftTLA"
                    ? member?.declName.baseName.sourceIdentifierName : nil)
            if constructor == "Refinement" {
                guard node.bindingSpecifier.text == "let" else {
                    context.diagnose(Diagnostic(node: Syntax(source), message: PropertyBindingDiagnostic()))
                    return binding
                }
                let labels = call.arguments.filter { $0.label?.text == "label" }
                let label = labels.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
                guard labels.isEmpty || (labels.count == 1 && label?.isEmpty == false) else {
                    context.diagnose(Diagnostic(node: Syntax(source), message: PropertyLabelDiagnostic()))
                    return binding
                }
                let argument = LabeledExprSyntax(label: .identifier("_name"), colon: .colonToken(),
                    expression: StringLiteralExprSyntax(content: name), trailingComma: .commaToken())
                call.arguments = LabeledExprListSyntax([argument] + Array(call.arguments))
                binding.initializer?.value = ExprSyntax(call)
                return binding
            }
            if let constructor,
               ["Invariant", "Reachable", "Always", "Eventually", "AlwaysEventually", "EventuallyAlways", "LeadsTo", "Temporal"].contains(constructor),
               call.arguments.allSatisfy({ $0.label?.text == "label" }), call.trailingClosure == nil {
                if !call.arguments.isEmpty {
                    guard call.arguments.count == 1,
                          let label = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                          !label.isEmpty else {
                        context.diagnose(Diagnostic(node: Syntax(source), message: PropertyLabelDiagnostic()))
                        return binding
                    }
                }
                guard node.bindingSpecifier.text == "let" else {
                    context.diagnose(Diagnostic(node: Syntax(source), message: PropertyBindingDiagnostic()))
                    return binding
                }
                var arguments = Array(call.arguments)
                if !arguments.isEmpty { arguments[arguments.count - 1].trailingComma = .commaToken() }
                arguments.append(LabeledExprSyntax(label: .identifier("_name"), colon: .colonToken(),
                    expression: StringLiteralExprSyntax(content: name)))
                call.arguments = LabeledExprListSyntax(arguments)
                binding.initializer?.value = ExprSyntax(call)
                return binding
            }
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.sourceIdentifierName == "parameter",
                  member.base?.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == parameterScope else { return binding }
            guard node.bindingSpecifier.text == "let" else {
                context.diagnose(Diagnostic(node: Syntax(source), message: ParameterBindingDiagnostic()))
                return binding
            }
            var arguments = Array(call.arguments)
            if !arguments.isEmpty { arguments[arguments.count - 1].trailingComma = .commaToken() }
            arguments.append(LabeledExprSyntax(label: .identifier("_name"), colon: .colonToken(),
                expression: StringLiteralExprSyntax(content: name), trailingComma: .commaToken()))
            arguments.append(argument("_sourceOffset", ExprSyntax(stringLiteral: String(source.positionAfterSkippingLeadingTrivia.utf8Offset)))
                .with(\.trailingComma, .commaToken()))
            arguments.append(argument("_sourceLength", ExprSyntax(stringLiteral: String(source.trimmedDescription.utf8.count))))
            call.arguments = LabeledExprListSyntax(arguments)
            binding.initializer?.value = ExprSyntax(call)
            return binding
        })
        return DeclSyntax(visited)
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
              binding.initializer != nil,
              let location = context.location(of: sources[index])
        else {
            context.diagnose(Diagnostic(node: Syntax(sources[index]), message: StepBindingDiagnostic()))
            return CodeBlockItemListSyntax(items)
        }
        let rest = savingBindings(Array(items.dropFirst(index + 1)),
            original: Array(sources.dropFirst(index + 1)))
        var prefix = Array(items.prefix(index))
        // Keep each initializer as its own inference boundary. Inlining it into
        // nested generic Let calls makes Swift solve the whole step at once.
        let temporary = context.makeUniqueName("savedValue")
        var savedBinding = binding
        savedBinding.pattern = PatternSyntax(IdentifierPatternSyntax(identifier: temporary))
        var savedDeclaration = declaration
        savedDeclaration.bindings = PatternBindingListSyntax([savedBinding])
        savedDeclaration.trailingTrivia = .newline
        prefix.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(savedDeclaration))))
        let value = ExprSyntax(DeclReferenceExprSyntax(baseName: temporary))
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
        return expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName
            ?? expression.as(MemberAccessExprSyntax.self)?.declName.baseName.sourceIdentifierName
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

private struct ParameterBindingDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-parameter-binding")
    let severity: DiagnosticSeverity = .error
    let message = "A model parameter must be an immutable named let binding in the specification scope."
}

private struct StateBindingDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-state-binding")
    let severity: DiagnosticSeverity = .error
    let message = "A state handle must be an immutable named let binding. Use Assign to update its value."
}

private struct PropertyBindingDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-property-binding")
    let severity: DiagnosticSeverity = .error
    let message = "A property handle must be an immutable named let binding."
}

private struct PropertyLabelDiagnostic: DiagnosticMessage {
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-property-label")
    let severity: DiagnosticSeverity = .error
    let message = "A property label requires one nonempty string literal without interpolation."
}

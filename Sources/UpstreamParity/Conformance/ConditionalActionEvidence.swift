import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum ConditionalActionEvidence {
    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: Data,
        proofSource: Data, to directory: URL) throws {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard TLCReferencePin.isRevision(sourceSHA) else { throw InitialFailureEvidenceError.invalidSourceSHA }
        guard !nativeSource.contains(0), let native = String(data: nativeSource, encoding: .utf8),
              let proof = String(data: proofSource, encoding: .utf8) else { throw invalid }
        let file = Parser.parse(source: native)
        guard !file.hasError else { throw invalid }
        let compilation = try GeneratedScalarConditionalProofModel.spec.compile()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) {
            switch $0 {
            case "Int", "Swift.Int": .int
            case "Bool", "Swift.Bool": .bool
            default: throw invalid
            }
        }
        let program = try CompiledProgram(inputs: inputs)
        let rendered = try GeneratedScalarConditionalProofModel.render().tlaBundle
        guard case .compiled(let identity, _, _) = rendered.provenance,
              identity == program.identity, rendered.imports.isEmpty,
              rendered.root.tla.utf8.elementsEqual(try program.renderModule().renderedModuleSource.utf8),
              program.behavior.actions.count == 1, let action = program.behavior.actions.first,
              case .ifElse(let predicate, let yes, let no) = action.body,
              predicate.resultType == .bool, predicate.operation == .lessThan,
              predicate.children.count == 2 else { throw invalid }

        func read(_ expression: CompiledExpression) throws -> String {
            guard expression.resultType == .int, expression.children.isEmpty,
                  case .stateVariable(let id) = expression.operation,
                  let field = program.layout.variables.first(where: { $0.id == id && $0.declaration.origin == .source }) else {
                throw invalid
            }
            return try nativeSourceIdentifier(field.declaration.name)
        }
        let left = try read(predicate.children[0]), right = try read(predicate.children[1])
        let conditionWords = Parser.parse(source: "(state.state.\(left) < state.state.\(right))")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)

        func unique<T>(_ matches: [T]) throws -> T {
            guard matches.count == 1, let match = matches.first else { throw invalid }
            return match
        }
        let visitor = try unique(file.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.filter {
            $0.name.text == "_visitUpdates\(action.id.ordinal)"
        })
        let parts = visitor.body?.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) } ?? []
        func part(_ id: Int) throws -> CodeBlockItemListSyntax {
            let declaration = try unique(parts.filter { $0.name.text == "_actionPart\(id)" })
            guard let statements = declaration.body?.statements, statements.count == 1,
                  let body = statements.first?.item.as(DoStmtSyntax.self)?.body.statements else {
                throw invalid
            }
            return body
        }
        let root = try part(0)
        guard root.count == 1, let item = root.first?.item else { throw invalid }
        let expression = item.as(TryExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self)
        guard let expression, let visit = nativeConditionalVisit(Syntax(expression)),
              visit.predicate == conditionWords,
              visit.ifTrue.arguments == ["updates", "emit"], visit.ifFalse.arguments == ["updates", "emit"] else {
            throw invalid
        }

        func branch(_ id: Int, _ compiled: CompiledActionExpr) throws -> Bool {
            guard case .define(let binder, let value, _) = compiled,
                  case .value(.boolean(let expected)) = value.operation,
                  let name = program.binderNames[binder] else { throw invalid }
            let statements = try part(id)
            guard statements.count == 2, let binding = statements.first?.item.as(VariableDeclSyntax.self),
                  binding.bindingSpecifier.text == "let", binding.bindings.count == 1,
                  let capture = binding.bindings.first,
                  let identifier = capture.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  identifier == "_\(name)_\(binder.ordinal)",
                  let actual = capture.initializer?.value.as(BooleanLiteralExprSyntax.self)?.literal.text,
                  actual == String(expected) else { throw invalid }
            return actual == "true"
        }
        let yesValue = try branch(visit.ifTrue.id, yes), noValue = try branch(visit.ifFalse.id, no)
        let childIDs = "<<\(visit.ifTrue.id), \(visit.ifFalse.id)>>"
        let values = "[child \\in {\(visit.ifTrue.id), \(visit.ifFalse.id)} |-> "
            + "IF child = \(visit.ifTrue.id) THEN \(yesValue ? "TRUE" : "FALSE") ELSE \(noValue ? "TRUE" : "FALSE")]"
        let header = "MODULE GeneratedScalarConditionalProof"
        let input = "CONSTANT NativeChooseChildren, NativeChooseValues"
        guard proof.components(separatedBy: header).count == 2,
              proof.components(separatedBy: input).count == 2,
              let footer = proof.split(separator: "\n").last, footer.allSatisfy({ $0 == "=" }),
              let terminal = proof.range(of: String(footer), options: .backwards) else { throw invalid }
        let concrete = String(proof[..<terminal.lowerBound])
            .replacingOccurrences(of: header, with: "MODULE GeneratedScalarConditionalNative")
            .replacingOccurrences(of: input, with: "NativeChooseChildren == \(childIDs)\nNativeChooseValues == \(values)")
            + """

        THEOREM ActualConditionalPreservesCompleteLabeledStep ==
            ASSUME ModelStateType, NEW label
            PROVE /\\ (RenderedLabeledStep(label) <=> SourceLabeledStep(label))
                  /\\ (NativeChooseLabeledStep(label) <=> SourceLabeledStep(label))
            BY ConditionalPreservesCompleteLabeledStep, SMT DEF NativeChooseChildren, NativeChooseValues

        ====

        """
        let model = Data(rendered.root.tla.utf8)
        let generatedProof = Data(concrete.utf8)
        let receipt = [
            "sourceSHA": sourceSHA,
            "sourceCompilationIdentity": identity.description,
            "authoredSourceSHA256": SHA256.hex(authoredSource),
            "nativeSourceSHA256": SHA256.hex(nativeSource),
            "proofTemplateSHA256": SHA256.hex(proofSource),
            "modelSHA256": SHA256.hex(model),
            "proofSHA256": SHA256.hex(generatedProof)
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in [
            ("authored-conditional-source.swift", authoredSource), ("native-conditional-source.swift", nativeSource),
            ("GeneratedScalarConditionalProofModel.tla", model), ("GeneratedScalarConditionalNative.tla", generatedProof),
            ("conditional-preparation.json", try JSONEncoder().encode(receipt))
        ] {
            try data.write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
        }
    }
}

private struct NativeConditionalVisit {
    struct Continuation {
        let id: Int
        let arguments: [String]
    }

    let predicate: [String]
    let ifTrue: Continuation
    let ifFalse: Continuation
}

// Check the labels and closures of the actual call before interpreting their children.
private func nativeConditionalVisit(_ syntax: Syntax?) -> NativeConditionalVisit? {
    func words(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).map(\.text)
    }
    func directCall(_ attempt: TryExprSyntax) -> FunctionCallExprSyntax? {
        guard attempt.questionOrExclamationMark == nil,
              let call = attempt.expression.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { return nil }
        return call
    }
    func closure(_ argument: LabeledExprSyntax, label: String?) -> ClosureExprSyntax? {
        guard argument.label?.text == label,
              let value = argument.expression.as(ClosureExprSyntax.self),
              value.signature == nil, value.statements.count == 1 else { return nil }
        return value
    }
    func branch(_ argument: LabeledExprSyntax, label: String) -> NativeConditionalVisit.Continuation? {
        guard let body = closure(argument, label: label)?.statements.first?.item,
              let attempt = body.as(TryExprSyntax.self)
                ?? body.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
              let call = directCall(attempt),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let id = Int(name.dropFirst("_actionPart".count)), name == "_actionPart\(id)" else { return nil }
        let arguments = call.arguments.compactMap { argument -> String? in
            guard argument.label == nil,
                  let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                  reference.argumentNames == nil else { return nil }
            return reference.baseName.text
        }
        guard arguments.count == call.arguments.count else { return nil }
        return .init(id: id, arguments: arguments)
    }
    guard let attempt = syntax?.as(TryExprSyntax.self), !attempt.hasError,
          let call = directCall(attempt),
          words(call.calledExpression) == ["SwiftTLA", ".", "_NativeMachineOperations", ".", "visitConditional"],
          call.arguments.count == 3 else { return nil }
    let arguments = Array(call.arguments)
    guard let predicate = closure(arguments[0], label: nil),
          let ifTrue = branch(arguments[1], label: "ifTrue"),
          let ifFalse = branch(arguments[2], label: "ifFalse"),
          ifTrue.id != ifFalse.id else { return nil }
    return .init(predicate: words(predicate.statements), ifTrue: ifTrue, ifFalse: ifFalse)
}

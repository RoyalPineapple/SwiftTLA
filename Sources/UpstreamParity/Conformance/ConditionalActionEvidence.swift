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
              let proof = String(data: proofSource, encoding: .utf8),
              let authored = String(data: authoredSource, encoding: .utf8),
              let physical = try AuthoredCopySyntax.conditionalProofInput(
                  source: authored, modelName: String(describing: GeneratedScalarConditionalProofModel.self))
        else { throw invalid }
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
              case .ifElse(let predicate, _, _) = action.body,
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

        let actual = try nativeConditionalActionPlans(native, program: program, predicate: conditionWords)
        let header = "MODULE GeneratedScalarConditionalProof"
        let input = "CONSTANT NativeChooseChildren, NativeChoosePlans, NativeChooseFields"
        guard proof.components(separatedBy: header).count == 2,
              proof.components(separatedBy: input).count == 2,
              let footer = proof.split(separator: "\n").last, footer.allSatisfy({ $0 == "=" }),
              let terminal = proof.range(of: String(footer), options: .backwards) else { throw invalid }
        let concrete = String(proof[..<terminal.lowerBound])
            .replacingOccurrences(of: header, with: "MODULE GeneratedScalarConditionalNative")
            .replacingOccurrences(of: input, with: """
                NativeChooseChildren == \(actual.children)
                NativeChoosePlans == \(actual.plans)
                NativeChooseFields == \(actual.fields)
                """)
            + """

        PhysicalConditional == \(physical)
        PhysicalOperand(term) == CopyReferenceValue(NativeChooseBefore, <<>>, term)
        PhysicalGuard ==
            LET term == PhysicalConditional.predicate IN
            CASE term[1] = "lessThan" -> PhysicalOperand(term[2]) < PhysicalOperand(term[3])
              [] term[1] = "equal" -> PhysicalOperand(term[2]) = PhysicalOperand(term[3])
              [] OTHER -> FALSE
        PhysicalArm(update) ==
            /\\ NativeChooseAfter[update[1]] = PhysicalOperand(update[2])
            /\\ \\A field \\in PhysicalConditional.fields \\ {update[1]} :
                   NativeChooseAfter[field] = NativeChooseBefore[field]
        PhysicalSourceLabeledStep(label) ==
            /\\ label = PhysicalConditional.label
            /\\ SourceConditionalStep(TRUE, PhysicalGuard,
                    PhysicalArm(PhysicalConditional.ifTrue), PhysicalArm(PhysicalConditional.ifFalse))

        THEOREM PhysicalSourceMatchesTheSourceRule ==
            ASSUME ModelStateType, NEW label
            PROVE PhysicalSourceLabeledStep(label) <=> SourceLabeledStep(label)
        PROOF
        <1>predicate. PhysicalGuard = (left < right)
            BY ONLY SMT DEF PhysicalGuard, PhysicalConditional, PhysicalOperand, CopyReferenceValue, NativeChooseBefore
        <1>yes. PhysicalArm(PhysicalConditional.ifTrue) <=> (UNCHANGED <<left, right>> /\\ selected' = TRUE)
            BY ONLY SMT DEF PhysicalArm, PhysicalConditional, PhysicalOperand,
                            CopyReferenceValue, NativeChooseBefore, NativeChooseAfter
        <1>no. PhysicalArm(PhysicalConditional.ifFalse) <=> (UNCHANGED <<left, right>> /\\ selected' = FALSE)
            BY ONLY SMT DEF PhysicalArm, PhysicalConditional, PhysicalOperand,
                            CopyReferenceValue, NativeChooseBefore, NativeChooseAfter
        <1>label. PhysicalConditional.label = "choose"
            BY ONLY SMT DEF PhysicalConditional
        <1>. QED BY <1>predicate, <1>yes, <1>no, <1>label, SMT
                    DEF PhysicalSourceLabeledStep, SourceLabeledStep, SourceChoose, SourceConditionalStep, ModelStateType

        THEOREM ActualConditionalPreservesCompleteLabeledStep ==
            ASSUME ModelStateType, NEW label
            PROVE /\\ (RenderedLabeledStep(label) <=> PhysicalSourceLabeledStep(label))
                  /\\ (NativeChooseLabeledStep(label) <=> PhysicalSourceLabeledStep(label))
            PROOF
            <1>fields. NativeChooseFields = {"left", "right", "selected"}
                BY SMT DEF NativeChooseFields
            <1>arms. /\\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[1]], TRUE)
                      /\\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[2]], FALSE)
                BY SMT DEF ExpectedNativeChoosePlan, NativeChoosePlans, NativeChooseChildren
            <1>backends. /\\ (RenderedLabeledStep(label) <=> SourceLabeledStep(label))
                         /\\ (NativeChooseLabeledStep(label) <=> SourceLabeledStep(label))
                BY <1>fields, <1>arms, ConditionalPreservesCompleteLabeledStep, SMT
            <1>. QED BY <1>backends, PhysicalSourceMatchesTheSourceRule, SMT

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

struct NativeConditionalVisit {
    struct Continuation {
        let id: Int
        let arguments: [String]
    }

    let predicate: [String]
    let ifTrue: Continuation
    let ifFalse: Continuation
}

// Check the labels and closures of the actual call before interpreting their children.
func nativeConditionalVisit(_ syntax: Syntax?) -> NativeConditionalVisit? {
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

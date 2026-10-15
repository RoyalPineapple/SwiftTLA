import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Expression conditional preservation")
struct ExpressionConditionalFailureProofTests {
    @Test("Generated conditional expression matches the proof inputs")
    func generatedConditionalExpressionProofInputs() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "ExpressionConditionalFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        func actionValues(_ action: CompiledActionExpr) -> [CompiledExpression] {
            switch action {
            case .assign(_, let value): return [value]
            case .guard_(let condition): return [condition]
            case .existsAction(_, let domain, let body), .define(_, let domain, let body):
                return [domain] + actionValues(body)
            case .ifElse(let condition, let yes, let no):
                return [condition] + actionValues(yes) + actionValues(no)
            case .and(let yes, let no), .or(let yes, let no):
                return actionValues(yes) + actionValues(no)
            case .unchanged: return []
            }
        }
        func conditionals(in value: CompiledExpression) -> [CompiledExpression] {
            let selected: [CompiledExpression]
            if case .ifThenElse = value.operation { selected = [value] } else { selected = [] }
            return selected + value.children.flatMap(conditionals)
        }
        let action = try #require(compiled.program.behavior.actions.first)
        let loweredConditionals = actionValues(action.body).flatMap(conditionals)
        #expect(loweredConditionals.count == 1)
        let value = try #require(loweredConditionals.first)
        guard value.children.count == 3,
              case .equal = value.children[0].operation,
              case .choose = value.children[1].operation,
              case .modulo = value.children[2].operation else {
            Issue.record("The source expression no longer lowers to the proved conditional rule")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let update = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let closedChoice = try #require(members.first {
            $0.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                .as(IdentifierPatternSyntax.self)?.identifier.text == "_closedChoice0"
        })
        let proofDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics")
            .standardizedFileURL
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        let visitor = try String(contentsOf:
            proofDirectory.appendingPathComponent("ExpressionConditionalFailureSwiftVisitor.txt"),
            encoding: .utf8)
        #expect(tokens(update.description) == tokens(visitor))
        let reversedSwiftBranch = update.description.replacingOccurrences(
            of: "((state.state.mode == 1) ? (try Self._closedChoice0.get()) :",
            with: "((state.state.mode != 1) ? (try Self._closedChoice0.get()) :")
        #expect(reversedSwiftBranch != update.description)
        #expect(tokens(reversedSwiftBranch) != tokens(visitor))
        let swiftBinder = try Regex(#"___binder_SpecParser_[0-9]+_0_1"#)
        let normalizedChoice = closedChoice.description.replacing(swiftBinder, with: "__PROOF_MEMBER__")
        let choice = try String(contentsOf:
            proofDirectory.appendingPathComponent("ExpressionConditionalFailureSwiftChoice.txt"),
            encoding: .utf8)
        #expect(tokens(normalizedChoice) == tokens(choice))

        let tlaBinder = try Regex(#"__binder_SpecParser_[0-9]+_0"#)
        let rendered = try ExpressionConditionalFailureModel.render()
        let normalizedTLA = rendered.tlaBundle.root.tla.replacing(tlaBinder, with: "__PROOF_MEMBER__")
        let formal = try String(contentsOf:
            proofDirectory.appendingPathComponent("ExpressionConditionalFailureModel.tla"),
            encoding: .utf8)
        #expect(normalizedTLA == formal)
        let eagerChoiceFailure = normalizedTLA.replacingOccurrences(
            of: #"__SwiftTLAChoiceFailure0 == ~((IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE TRUE))"#,
            with: #"__SwiftTLAChoiceFailure0 == ~((IF (mode = 1) THEN (\E __PROOF_MEMBER__ \in {1} : FALSE) ELSE FALSE))"#)
        #expect(eagerChoiceFailure != normalizedTLA)
        #expect(eagerChoiceFailure != formal)
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }
}

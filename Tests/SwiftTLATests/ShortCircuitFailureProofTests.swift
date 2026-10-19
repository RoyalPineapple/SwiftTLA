import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Short-circuit failure preservation")
struct ShortCircuitFailureProofTests {
    @Test("Generated Boolean steps match the proof inputs")
    func generatedBooleanStepProofInputs() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "ShortCircuitFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        func guards(in action: CompiledActionExpr) -> [CompiledExpression] {
            switch action {
            case .guard_(let value): return [value]
            case .existsAction(_, _, let body), .define(_, _, let body): return guards(in: body)
            case .ifElse(_, let yes, let no), .and(let yes, let no), .or(let yes, let no):
                return guards(in: yes) + guards(in: no)
            case .assign, .unchanged: return []
            }
        }
        let actions = compiled.program.behavior.actions
        #expect(actions.count == 2)
        let conjunction = try #require(actions.first)
        let disjunction = try #require(actions.last)
        let conjunctionGuard = try #require(guards(in: conjunction.body).first)
        let disjunctionGuard = try #require(guards(in: disjunction.body).first)
        guard case .and = conjunctionGuard.operation,
              case .or = disjunctionGuard.operation else {
            Issue.record("The source Boolean steps no longer lower to the proved short-circuit rules")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let proofDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics")
            .standardizedFileURL
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        for index in 0..<2 {
            let visitor = try #require(members.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(index)"
            })
            let name = index == 0
                ? "ShortCircuitConjunctionSwiftVisitor.txt"
                : "ShortCircuitDisjunctionSwiftVisitor.txt"
            let witness = try String(contentsOf: proofDirectory.appendingPathComponent(name),
                encoding: .utf8)
            #expect(tokens(visitor.description) == tokens(witness))
            let reversed = visitor.description.replacingOccurrences(
                of: index == 0 ? "guard left else" : "guard !left else",
                with: index == 0 ? "guard !left else" : "guard left else")
            #expect(reversed != visitor.description)
            #expect(tokens(reversed) != tokens(witness))
            let action = actions[index]
            let parts = try emitter.actionFunctions(action.body)
            let wrongVisitor = try #require(Parser.parse(source: reversed)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                    program: compiled.program, stateFields: emitter.stateMemberNames,
                    parts: parts.writes, conditions: parts.conditions)
                Issue.record("A short-circuit guard reversed its compiled left test")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.guard."))
            }
            let changedLeaf = visitor.description.replacingOccurrences(of: "== 0)", with: "== 1)")
            #expect(changedLeaf != visitor.description)
            let wrongLeaf = try #require(Parser.parse(source: changedLeaf)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(wrongLeaf, action: action.body,
                    program: compiled.program, stateFields: emitter.stateMemberNames,
                    parts: parts.writes, conditions: parts.conditions)
                Issue.record("A short-circuit guard changed its compiled right operand")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.guard."))
            }
        }
        let rendered = try ShortCircuitFailureModel.render()
        let formal = try String(contentsOf:
            proofDirectory.appendingPathComponent("ShortCircuitFailureModel.tla"),
            encoding: .utf8)
        #expect(rendered.tlaBundle.root.tla == formal)
        let eagerConjunction = formal.replacingOccurrences(
            of: #"__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN divisor # 0 ELSE TRUE))"#,
            with: #"__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN divisor # 0 ELSE FALSE))"#)
        #expect(eagerConjunction != formal)
        #expect(eagerConjunction != rendered.tlaBundle.root.tla)
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }
}

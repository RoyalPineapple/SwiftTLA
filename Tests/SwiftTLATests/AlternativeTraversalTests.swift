import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import Testing

@Suite("Alternative traversal")
struct AlternativeTraversalTests {
    @Test("Successful updates survive a failing alternative")
    func mixedOutcomes() {
        var emitted: [Int] = []
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { emitted.append($0) }) { alternative, emit in
                try emit(alternative)
                try emit(alternative == 0 ? 0 : 2)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(emitted == [0, 0, 1, 2])
    }

    @Test("The Swift alternative kernel matches the proved ordered traversal")
    func kernelMatchesProofRule() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(contentsOf: directory.appendingPathComponent(
            "../../Sources/SwiftTLA/NativeMachineOperations.swift").standardizedFileURL, encoding: .utf8)
        let parsed = Parser.parse(source: source)
        let owner = try #require(parsed.statements.compactMap {
            $0.item.as(EnumDeclSyntax.self)
        }.first { $0.name.text == "_NativeMachineOperations" })
        let actual = try #require(owner.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }.first { $0.name.text == "visitAlternatives" })
        let witness = try String(contentsOf: directory.appendingPathComponent(
            "../../Verification/Semantics/AlternativeTraversalSwiftKernel.txt").standardizedFileURL,
            encoding: .utf8)
        let expected = try #require(Parser.parse(source: witness).statements.first?
            .item.as(FunctionDeclSyntax.self))
        let expectedTokens = expected.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actual.tokens(viewMode: .sourceAccurate).map(\.text) == expectedTokens)

        let reversed = actual.description.replacingOccurrences(
            of: "for update in updates { try emit(update) }",
            with: "for update in updates.reversed() { try emit(update) }")
        #expect(reversed != actual.description)
        let mutant = try #require(Parser.parse(source: reversed).statements.first?
            .item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != expectedTokens)
    }

    @Test("An output callback error is not treated as a model failure")
    func callbackFailure() {
        var visited: [Int] = []
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { (_: Int) in
                throw NativeMachineEvaluationError.noMatchingCase
            }) { alternative, emit in
                visited.append(alternative)
                try emit(alternative)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(visited == [0])
    }
}

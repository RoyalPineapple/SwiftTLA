import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import Testing

@Suite("Conditional transition operation")
struct ConditionalKernelTests {
    @Test("The actual Swift operation is the reviewed conditional rule")
    func kernelMatchesProofRule() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(contentsOf: directory.appendingPathComponent(
            "../../Sources/SwiftTLA/NativeMachineOperations.swift").standardizedFileURL, encoding: .utf8)
        let owner = try #require(Parser.parse(source: source).statements.compactMap {
            $0.item.as(EnumDeclSyntax.self)
        }.first { $0.name.text == "_NativeMachineOperations" })
        let actual = try #require(owner.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }.first { $0.name.text == "visitConditional" })
        let witness = try String(contentsOf: directory.appendingPathComponent(
            "../../Verification/Semantics/ConditionalSwiftKernel.txt").standardizedFileURL, encoding: .utf8)
        let expected = try #require(Parser.parse(source: witness).statements.first?
            .item.as(FunctionDeclSyntax.self))
        #expect(actual.tokens(viewMode: .sourceAccurate).map(\.text)
            == expected.tokens(viewMode: .sourceAccurate).map(\.text))
    }

    @Test("Condition is evaluated once and only its selected branch runs")
    func selectedBranch() throws {
        for selected in [false, true] {
            var evaluations = 0
            var emitted: [Int] = []
            try _NativeMachineOperations.visitConditional({
                evaluations += 1
                return selected
            }, ifTrue: {
                emitted.append(1)
            }, ifFalse: {
                emitted.append(0)
            })
            #expect(evaluations == 1)
            #expect(emitted == [selected ? 1 : 0])
        }
    }

    @Test("A failing condition runs neither branch")
    func conditionFailure() {
        var emitted: [Int] = []
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.visitConditional({
                throw NativeMachineEvaluationError.divisionByZero
            }, ifTrue: {
                emitted.append(1)
            }, ifFalse: {
                emitted.append(0)
            })
        }
        #expect(emitted.isEmpty)
    }
}

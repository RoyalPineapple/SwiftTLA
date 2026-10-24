import Foundation
import Testing
@testable import SwiftTLA

@Suite("Initial branch failures")
struct InitialBranchFailureTests {
    @Test("A failed dependent expression does not discard its valid initial sibling")
    func preservesValidInitialSibling() throws {
        let generated = try DependentDivisionInitialModel.initialOutcomes()
        #expect(generated.states.map(\.state) == [.init(divisor: 1, quotient: 1)])
        #expect(generated.firstFailure == .divisionByZero)

        let compilation = try DependentDivisionInitialModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let quotient = try #require(compilation.layout.testVariableID(named: "quotient"))
        #expect(try compiled.states[0].value(for: quotient) == .integer(1))
    }

    @Test("Rendered dependent division retains its initial failure outcome")
    func renderedDependentDivisionFailure() throws {
        let tla = try DependentDivisionInitialModel.render().tlaBundle.tla
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/DependentDivisionInitialModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: fixture, encoding: .utf8)
        #expect(tla == checkedModule)
    }

    @Test("Rendered selected initial invariant retains its failed branch")
    func renderedSelectedInvariantFailure() throws {
        let tla = try SelectedInitialInvariantFailureModel.render().tlaBundle.tla
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/SelectedInitialInvariantFailureModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: fixture, encoding: .utf8)
        #expect(tla == checkedModule)
    }

    @Test("A selected invariant failure retains its valid initial sibling")
    func preservesValidSiblingWhenSelectedInvariantFails() throws {
        let generated = try SelectedInitialInvariantFailureModel.initialOutcomes()
        #expect(generated.states.map(\.state) == [.init(divisor: 1, quotient: 1)])
        #expect(generated.firstFailure == .divisionByZero)

        let compilation = try SelectedInitialInvariantFailureModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let divisor = try #require(compilation.layout.testVariableID(named: "divisor"))
        #expect(try compiled.states[0].value(for: divisor) == .integer(1))
    }

    @Test("An earlier branch's invariant failure precedes a later initializer failure")
    func preservesFirstFailureOrderAcrossBranches() throws {
        let generated = try InitialFailureOrderModel.initialOutcomes()
        #expect(generated.states.isEmpty)
        #expect(generated.firstFailure == .negativeModuloDivisor(-1))

        let compiled = try CompiledRuntime(compilation: InitialFailureOrderModel.spec.compile()).initialOutcomes()
        #expect(compiled.states.isEmpty)
        #expect(compiled.firstFailure == generated.firstFailure)
    }

    @Test("An out-of-domain function read retains the valid initial branch")
    func preservesValidFunctionReadSibling() throws {
        let generated = try DependentFunctionReadInitialModel.initialOutcomes()
        #expect(generated.states.count == 1)
        #expect(generated.states[0].state.key == 0)
        #expect(generated.states[0].state.result == 42)
        #expect(generated.firstFailure == .functionArgumentOutsideDomain)

        let compilation = try DependentFunctionReadInitialModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let key = try #require(compilation.layout.testVariableID(named: "key"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        #expect(try compiled.states[0].value(for: key) == .integer(0))
        #expect(try compiled.states[0].value(for: result) == .integer(42))
    }

    @Test("A later initial overflow remains visible after an earlier checked addition")
    func preservesFailureAfterFallibleInitialPrefix() throws {
        let generated = try CheckedAdditionPrefixInitialModel.initialOutcomes()
        #expect(generated.states.isEmpty)
        #expect(generated.firstFailure == .integerOverflow(.addition,
            operands: [3, Int.max]))

        let rendered = try CheckedAdditionPrefixInitialModel.render().tlaBundle.root.tla
        let failures = rendered.split(separator: "\n").filter {
            $0.hasPrefix("__SwiftTLAInitialOverflowFailure3(")
        }
        let failure = try #require(failures.count == 1 ? failures[0] : nil)
        #expect(failure.contains("THEN (LET __SwiftTLAInitialValue2 =="))
        #expect(rendered.contains("__SwiftTLAInitialOverflowOperation3 == \"addition\""))
    }

    @Test("An invalid compiled value shape is not relabeled as a model failure")
    func rejectsUnmappedFailure() {
        #expect(throws: EvalError.expected(.integer, actual: [])) {
            try _NativeMachineOperations.visitInitialBranch {
                throw EvalError.expected(.integer, actual: [])
            } onEvaluationFailure: { _ in
                Issue.record("An internal value-shape error must not become an initial outcome")
            }
        }
    }
}

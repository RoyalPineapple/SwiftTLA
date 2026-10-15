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

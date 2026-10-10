import Foundation
import Testing
@testable import SwiftTLA

struct TypedSelectionTests {
    @Test("Selection reads the current generated state and fails without a matching member")
    func selectionUsesCurrentState() throws {
        var machine = try IncreasingSelection.makeMachine()
        for _ in 0..<3 {
            guard machine.state.position < 3 else { break }
            let previous = machine.state.position
            #expect(try machine.enabledActions() == [.advance])
            _ = try machine.send(.advance)
            #expect(machine.state.position == previous + 1)
        }
        #expect(machine.state.position == 3)
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) { _ = try machine.send(.advance) }
        #expect(machine.snapshot == before)
    }

    @Test("Rendered integer selection chooses the same least matching member")
    func renderedSelectionUsesLeastMember() throws {
        let module = try IncreasingSelection.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/IncreasingSelection.tla")
            .standardizedFileURL
        #expect(module == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("An empty matching domain fails when the choice is evaluated")
    func missingSelectionFailsDuringEvaluation() throws {
        let choice = Select(from: SetExpr<Int>.literal(1)) { _ in false }
        #expect(throws: EvalError.noSatisfyingChoice) { try evaluateClosed(choice.stateExpr) }
    }

    @Test("A closed missing selection fails only when its generated action runs")
    func closedMissingSelectionDoesNotChangeTheMachine() throws {
        var machine = try ClosedMissingSelection.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            _ = try machine.send(.advance)
        }
        #expect(machine.snapshot == before)
    }
}

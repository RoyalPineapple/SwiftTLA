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

    @Test("Integer selection retains its compiled choice and exact formal output")
    func renderedSelectionUsesLeastMember() throws {
        let compilation = try IncreasingSelection.spec.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .define(_, let choice, _) = action.body,
              case .choose = choice.operation else {
            Issue.record("The authored selection no longer lowers to the proved choice rule")
            return
        }
        #expect(choice.children.count == 2)
        let module = try IncreasingSelection.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/IncreasingSelection.tla")
            .standardizedFileURL
        #expect(module == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("Authored PlusCal guards empty choice before evaluating it")
    func plusCalGuardsSelectionFailure() throws {
        let rendered = try IncreasingSelection.render()
        let direct = rendered.tlaBundle.root.tla
        let plusCal = try rendered.plusCalBundle().root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/IncreasingSelectionPlusCal.tla")
            .standardizedFileURL
        #expect(plusCal.replacingOccurrences(of: "MODULE IncreasingSelection ----",
            with: "MODULE IncreasingSelectionPlusCal ----")
            == (try String(contentsOf: proofInput, encoding: .utf8)))
        let failure = try #require(direct.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAChoiceFailure0 ==")
        })
        #expect(plusCal.split(separator: "\n").contains(failure))
        let action = try #require(direct.split(separator: "\n").first { $0.hasPrefix("advance ==") })
        let guardStart = try #require(action.range(of: "IF "))
        let guardEnd = try #require(action.range(of: " THEN "))
        let condition = action[guardStart.upperBound..<guardEnd.lowerBound]
        let lines = plusCal.split(separator: "\n")
        let choiceLine = try #require(lines.firstIndex { $0.contains("with (__atomic_0 =") && $0.contains("(CHOOSE ") })
        #expect(choiceLine > 0)
        if choiceLine > 0 {
            #expect(lines[choiceLine - 1].trimmingCharacters(in: .whitespaces) == "when \(condition);")
        }
    }

    @Test("Boolean selection prefers false in both generated outputs")
    func booleanSelectionUsesLeastMember() throws {
        var machine = try BooleanSelection.makeMachine()
        #expect(machine.state.flag)
        _ = try machine.send(.select)
        #expect(!machine.state.flag)

        let module = try BooleanSelection.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/BooleanSelection.tla")
            .standardizedFileURL
        #expect(module == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("An empty matching domain fails when the choice is evaluated")
    func missingSelectionFailsDuringEvaluation() throws {
        let choice = Select(from: SetExpr<Int>.literal(1)) { _ in false }
        #expect(throws: EvalError.noSatisfyingChoice) { try evaluateClosed(choice.stateExpr) }
    }

    @Test("An empty selection fails transactionally with action identity during checking")
    func closedMissingSelectionDoesNotChangeTheMachine() throws {
        var machine = try ClosedMissingSelection.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            _ = try machine.send(.advance)
        }
        #expect(machine.snapshot == before)
        var observedFailure = false
        let result = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            if case .evaluationFailure(let source, let action, let reason) = event {
                observedFailure = true
                #expect(source == 0 && action == .advance && reason == .noSatisfyingChoice)
            }
        }
        #expect(observedFailure)
        #expect(result.completion == .evaluationFailure(.noSatisfyingChoice))
        #expect(result.states == 1 && result.edges == 0)
    }

    @Test("A nested empty selection fails natively and emits a TLA failure check")
    func nestedMissingSelectionHasNoTransition() throws {
        var machine = try NestedMissingSelection.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            _ = try machine.send(.advance)
        }
        #expect(machine.snapshot == before)

        let rendered = try NestedMissingSelection.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(declarations.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
    }

    @Test("A successful nested selection emits a check for subsequent addition overflow")
    func nestedSelectionOverflowHasNoTransition() throws {
        var machine = try NestedOverflowSelection.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            _ = try machine.send(.advance)
        }
        #expect(machine.snapshot == before)

        let rendered = try NestedOverflowSelection.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(declarations.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
        #expect(declarations.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0 ==") })
        #expect(declarations.contains { $0.hasPrefix("__SwiftTLAOverflowOperands0 ==") })
    }
}

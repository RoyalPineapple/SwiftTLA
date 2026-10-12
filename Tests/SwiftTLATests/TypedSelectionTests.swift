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
        let direct = try compilation.render().tlaBundle.root.tla
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        #expect(direct.replacing(binder, with: "__SELECT_MEMBER__")
            == module.replacing(binder, with: "__SELECT_MEMBER__"))
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
        let compilation = try BooleanSelection.spec.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .and(.guard_(let control), let body) = action.body,
              case .equal = control.operation,
              case .define(_, let choice, _) = body,
              case .choose = choice.operation else {
            Issue.record("The authored Boolean selection no longer lowers to the proved choice rule")
            return
        }
        #expect(choice.children.count == 2)
        guard choice.children.count == 2 else { return }
        guard case .value(.set(let members)) = choice.children[0].computation.operation,
              case .value(.boolean(true)) = choice.children[1].computation.operation else {
            Issue.record("The authored Boolean domain and predicate did not survive lowering")
            return
        }
        #expect(members == Set([.boolean(false), .boolean(true)]))

        var machine = try BooleanSelection.makeMachine()
        #expect(machine.state.flag)
        #expect(try machine.enabledActions() == [.select])
        _ = try machine.send(.select)
        #expect(!machine.state.flag)
        #expect(try machine.enabledActions() == [.Terminating])
        let completed = machine.snapshot
        _ = try machine.send(.Terminating)
        #expect(machine.snapshot == completed)

        let module = try BooleanSelection.render().tlaBundle.root.tla
        let direct = try compilation.render().tlaBundle.root.tla
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        #expect(direct.replacing(binder, with: "__SELECT_MEMBER__")
            == module.replacing(binder, with: "__SELECT_MEMBER__"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/BooleanSelection.tla")
            .standardizedFileURL
        #expect(module == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("Enum selection uses the same canonical case order in Swift and TLA+")
    func enumSelectionUsesLeastMember() throws {
        let compilation = try EnumSelection.spec.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .and(.guard_, let body) = action.body,
              case .define(_, let choice, _) = body,
              case .choose = choice.operation else {
            Issue.record("The authored enum selection no longer lowers to the compiled choice rule")
            return
        }
        switch choice.resultType {
        case .finite(let members):
            #expect(members == [.string("alpha"), .string("zed")])
        case .named: break
        default:
            Issue.record("The enum selection lost its finite type during lowering: \(choice.resultType)")
            return
        }

        var machine = try EnumSelection.makeMachine()
        #expect(machine.state.selected == .zed)
        _ = try machine.send(.select)
        #expect(machine.state.selected == .alpha)

        let module = try EnumSelection.render().tlaBundle.root.tla
        let direct = try compilation.render().tlaBundle.root.tla
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        #expect(direct.replacing(binder, with: "__SELECT_MEMBER__")
            == module.replacing(binder, with: "__SELECT_MEMBER__"))
        let renderedAction = try #require(module.split(separator: "\n").first { $0.hasPrefix("select ==") })
        #expect(renderedAction.contains("= \"alpha\" -> 0 []"))
        #expect(renderedAction.contains("= \"zed\" -> 1"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EnumSelection.tla")
            .standardizedFileURL
        #expect(module == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("Closed String selection uses the same least value in Swift and TLA+")
    func stringSelectionUsesLeastMember() throws {
        let compilation = try StringSelection.spec.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .and(.guard_, let body) = action.body,
              case .define(_, let choice, _) = body,
              case .choose = choice.operation,
              let domain = choice.children.first,
              case .value(.set(let members)) = domain.computation.operation else {
            Issue.record("The authored String selection no longer lowers to a closed choice")
            return
        }
        #expect(members == Set([.string("alpha"), .string("zed")]))

        var machine = try StringSelection.makeMachine()
        #expect(machine.state.selected == "zed")
        _ = try machine.send(.select)
        #expect(machine.state.selected == "alpha")

        let module = try StringSelection.render().tlaBundle.root.tla
        let direct = try compilation.render().tlaBundle.root.tla
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        #expect(direct.replacing(binder, with: "__SELECT_MEMBER__")
            == module.replacing(binder, with: "__SELECT_MEMBER__"))
        let renderedAction = try #require(module.split(separator: "\n").first { $0.hasPrefix("select ==") })
        #expect(renderedAction.contains("= \"alpha\" -> 0 []"))
        #expect(renderedAction.contains("= \"zed\" -> 1"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EnumSelection.tla")
            .standardizedFileURL
        let provedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(module.replacingOccurrences(of: "StringSelection", with: "EnumSelection")
            .replacing(binder, with: "__SELECT_MEMBER__")
            == provedModule.replacing(binder, with: "__SELECT_MEMBER__"))
    }

    @Test("Closed sequence selection retains the lexicographically first complete value")
    func sequenceSelectionUsesLeastMember() throws {
        let compilation = try SequenceSelection.spec.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .and(.guard_, let body) = action.body,
              case .define(_, let choice, _) = body,
              case .choose = choice.operation else {
            Issue.record("The authored sequence selection no longer lowers to a choice")
            return
        }

        var machine = try SequenceSelection.makeMachine()
        #expect(machine.state.selected == [2])
        _ = try machine.send(.select)
        #expect(machine.state.selected == [1])

        let module = try SequenceSelection.render().tlaBundle.root.tla
        let direct = try compilation.render().tlaBundle.root.tla
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        #expect(direct.replacing(binder, with: "__SELECT_MEMBER__")
            == module.replacing(binder, with: "__SELECT_MEMBER__"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/SequenceSelection.tla")
            .standardizedFileURL
        let expected = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(module.replacing(binder, with: "__SELECT_MEMBER__")
            == expected.replacing(binder, with: "__SELECT_MEMBER__"))
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

    @Test("A missing String selection has the same evaluation failure in Swift and TLA+")
    func missingStringSelectionHasMatchingFailure() throws {
        var machine = try MissingStringSelection.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            _ = try machine.send(.select)
        }
        #expect(machine.snapshot == before)

        let rendered = try MissingStringSelection.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        let actual = rendered.tlaBundle.root.tla.replacing(binder, with: "__PROOF_MEMBER__")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/MissingStringSelection.tla")
            .standardizedFileURL
        #expect(actual == (try String(contentsOf: proofInput, encoding: .utf8)))
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

    @Test("Only the selected conditional branch can report an empty choice")
    func conditionalSelectionFailureIsBranchScoped() throws {
        let machines = try ConditionalSelectionFailure.initialMachines()
        #expect(machines.count == 2)
        for var machine in machines {
            let before = machine.snapshot
            if machine.state.attempt {
                #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
                    _ = try machine.send(.select)
                }
                #expect(machine.snapshot == before)
            } else {
                _ = try machine.send(.select)
                #expect(machine.state.selected == 2)
            }
        }

        let rendered = try ConditionalSelectionFailure.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalSelectionFailure.tla")
            .standardizedFileURL
        let actual = rendered.tlaBundle.root.tla.replacing(binder, with: "__SELECT_MEMBER__")
        let expected = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(actual == expected)
    }

    @Test("An empty choice in an If condition is a matching evaluation failure")
    func conditionalChoiceConditionFailureHasNoTransition() throws {
        var machine = try ConditionalChoiceConditionFailure.makeMachine()
        let before = machine.snapshot
        #expect(machine.state.selected == 0)
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            _ = try machine.send(.select)
        }
        #expect(machine.snapshot == before)

        let rendered = try ConditionalChoiceConditionFailure.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let binder = try Regex(#"__binder_(?:TypedSelectionFixtures|SpecParser)_[0-9]+_[0-9]+"#)
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalChoiceConditionFailure.tla")
            .standardizedFileURL
        let actual = rendered.tlaBundle.root.tla.replacing(binder, with: "__CONDITION_MEMBER__")
        let expected = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(actual == expected)
    }
}

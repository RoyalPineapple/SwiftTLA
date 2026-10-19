import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin
@testable import UpstreamParity

@Suite struct OrderedStepTests {
    @Test("Generated ordered writes retain the proved arithmetic and read order")
    func generatedOrderedWriteProofInput() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("OrderedStepFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "OrderedCopyModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let actions = compiled.program.behavior.actions
        let variable = try #require(compiled.program.layout.variables.first {
            $0.declaration.name == "x"
        })
        #expect(actions.count == 3)
        func captures(in node: CompiledActionExpr) -> [(BinderID, CompiledExpression)] {
            switch node {
            case .define(let id, let value, let body):
                return [(id, value)] + captures(in: body)
            case .and(let left, let right), .or(let left, let right),
                 .ifElse(_, let left, let right):
                return captures(in: left) + captures(in: right)
            case .existsAction(_, _, let body): return captures(in: body)
            case .assign, .unchanged, .guard_: return []
            }
        }
        for (index, action) in actions.prefix(2).enumerated() {
            let ordered = captures(in: action.body)
            guard ordered.count == 2 else {
                Issue.record("The ordered source step no longer has two captured writes")
                return
            }
            let first = ordered[0].0
            let firstValue = ordered[0].1
            let secondValue = ordered[1].1
            guard case .add = firstValue.operation,
                  firstValue.children.count == 2,
                  case .stateVariable(let read) = firstValue.children[0].operation,
                  case .value(.integer(1)) = firstValue.children[1].operation,
                  read == variable.id else {
                Issue.record("The ordered source step no longer lowers to the proved first addition")
                return
            }
            if index == 0 {
                guard case .boundValue(let copied) = secondValue.operation,
                      copied == first else {
                    Issue.record("The copy no longer reads the first checked result")
                    return
                }
            } else {
                guard case .add = secondValue.operation,
                      secondValue.children.count == 2,
                      case .boundValue(let prior) = secondValue.children[0].operation,
                      case .value(.integer(1)) = secondValue.children[1].operation,
                      prior == first else {
                    Issue.record("The second addition no longer reads the first checked result")
                    return
                }
            }
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let visitors = try ["_visitUpdates0", "_visitUpdates1", "_visitUpdates2"].map { name in
            try #require(members.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == name
            })
        }
        let dispatch = try #require(members.first {
            $0.description.contains("private func _visitSuccessors(for action: Action,")
        })
        let formalCall = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "formalCall"
        })
        let witness = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedCopySwiftVisitors.txt")
            .standardizedFileURL
        let expected = try String(contentsOf: witness, encoding: .utf8)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        let actual = (visitors + [dispatch, formalCall]).map(\.description).joined(separator: "\n")
        #expect(tokens(actual) == tokens(expected))
        let wrongSecondRead = visitors[1].description.replacingOccurrences(
            of: "let _arithmetic0: Int = ___atomic_2_2",
            with: "let _arithmetic0: Int = state.state.x")
        #expect(wrongSecondRead != visitors[1].description)
        #expect(tokens(([
            visitors[0].description, wrongSecondRead, visitors[2].description,
            dispatch.description, formalCall.description
        ]).joined(separator: "\n")) != tokens(expected))
        let secondAction = actions[1]
        let emittedWrites = try emitter.actionFunctions(secondAction.body).writes
        try verifyGeneratedActionWriteOutput(visitors[1], action: secondAction.body,
            program: compiled.program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
        let wrongSecondVisitor = try #require(Parser.parse(source: wrongSecondRead)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongSecondVisitor, action: secondAction.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
            Issue.record("A generated addition reread pre-step state instead of its inherited operand")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
            #expect(diagnostic.expected == "the captured value reads its compiled source")
        }
        let wrongRoute = dispatch.description.replacingOccurrences(
            of: "Self._visitSuccessors1", with: "Self._visitSuccessors0")
        #expect(wrongRoute != dispatch.description)
        #expect(tokens((visitors.map(\.description) + [wrongRoute, formalCall.description])
            .joined(separator: "\n")) != tokens(expected))
    }

    @Test("Later reads observe earlier writes in one atomic transition")
    func orderedReadsAndRepeatedWrites() throws {
        var machine = try OrderedCopyModel.makeMachine()
        let transition = try machine.send(.copy)
        #expect(transition.before.x == 1)
        #expect(transition.before.y == 0)
        #expect(transition.after.x == 2)
        #expect(transition.after.y == 2)
        let repeated = try machine.send(.repeatWrites)
        #expect(repeated.before == transition.after)
        #expect(repeated.after.x == 4)
        #expect(repeated.after.y == 2)
        let graph = try ReachabilityGraph(
            initialMachines: OrderedCopyModel.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 3)
        #expect(Set(graph.transitions.keys.map { [$0.state.x, $0.state.y] }) == [[1, 0], [2, 2], [4, 2]])
    }

    @Test("The checked repeated-write module matches normalized generated TLA")
    func renderedRepeatedWriteProofInput() throws {
        let rendered = try OrderedCopyModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedCopy.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(Int.min <= -2_000_000_000 && 2_000_000_000 <= Int.max)
        let normalized = rendered
            .replacingOccurrences(of: "EXTENDS Integers, FiniteSets, Sequences\n\nVARIABLES",
                with: "EXTENDS Integers, FiniteSets, Sequences\n\nCONSTANTS OrderedIntMin, OrderedIntMax\n\nVARIABLES")
            .replacingOccurrences(of: TLAValue.int(.min).description, with: "OrderedIntMin")
            .replacingOccurrences(of: TLAValue.int(.max).description, with: "OrderedIntMax")
        #expect(normalized == checkedModule)
    }

    @Test("A later checked addition reports the failing operands")
    func laterAdditionFailure() throws {
        let machine = try OrderedOverflowModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.successors(for: .advance)
        }

        let rendered = try OrderedOverflowModel.render()
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        let laterFailure = try #require(lines.first { $0.hasPrefix("__SwiftTLAOverflowFailure0_1 ==") })
        let operands = try #require(lines.first { $0.hasPrefix("__SwiftTLAOverflowOperands0_1 ==") })
        #expect(laterFailure.contains("LET __atomic_0 == (count + 1)"))
        #expect(operands.contains("<<__atomic_0, 1>>"))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }

    @Test("Nested checked additions retain the failing operation in both outputs")
    func nestedAdditionFailure() throws {
        let machine = try NestedAdditionOverflowModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.successors(for: .advance)
        }

        let rendered = try NestedAdditionOverflowModel.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.filter { $0.hasPrefix("__SwiftTLAOverflowFailure") }.count == 2)
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAOverflowOperands0_1 ==") && $0.contains("count + 1") })
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }

    @Test("Choices and following statements read their current branch values")
    func orderedChoice() throws {
        let machine = try OrderedGuardModel.makeMachine()
        let successors = try machine.successors(for: .choose)
        #expect(successors.count == 1)
        let next = try #require(successors.first)
        #expect(next.state.value == 2)
        #expect(next.state.copied == 2)
    }

    @Test("A later blocked guard discards every earlier write")
    func blockedBranchDoesNotCommit() throws {
        var machine = try OrderedBlockedModel.makeMachine()
        let before = machine.snapshot
        #expect(try machine.successors(for: .advance).isEmpty)
        #expect(throws: GeneratedMachineError.noMatchingSuccessor) {
            try machine.send(.advance)
        }
        #expect(machine.snapshot == before)
    }
    @Test("Assertions read the value at their position in the step")
    func assertionReadsUpdatedValue() throws {
        let graph = try ReachabilityGraph(
            initialMachines: OrderedAssertionModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.count == 2)
    }

    @Test("a failing algorithm assertion is a generated safety violation")
    func failingAssertionIsChecked() throws {
        guard case .counterexample(let result) = try ReachabilityGraph.check(
            initialMachines: FailingAssertionModel.initialMachines(), maximumStates: 2) else {
            Issue.record("Expected an assertion counterexample")
            return
        }
        guard case .invariant(let property) = try #require(result.violations.first) else {
            Issue.record("Expected the assertion to be checked as an invariant")
            return
        }
        #expect(FailingAssertionModel.formalPropertyNames[property] == "__pcal_assert_0")
        #expect(result.trace.count == 1)
    }

    @Test("Procedure arguments capture earlier writes in the caller")
    func callReadsUpdatedValue() throws {
        let scenario = try #require(OrderedCallModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 8)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.contains { $0.state.output == 7 })
        #expect(graph.transitions.keys.allSatisfy { $0.state.output == 0 || $0.state.output == 7 })
        let run = try NativeScenarioRun(scenario, maximumStates: 8)
        try run.validateExpectations()
        let rendered = try scenario.render()
        #expect(rendered.actions.contains { $0.sourceName == "procedure.copy.enter" && $0.emittedBaseName == "enter" })
        let emitted = Set(rendered.actions.map(\.emittedInvocationName))
        for transitions in graph.transitions.values {
            for transition in transitions {
                #expect(emitted.contains(try graph.formalCall(for: transition.action).description))
            }
        }
        _ = try rendered.plusCalBundle()
    }

    @Test("Ordinary let captures at its declaration and preserves shadowed values")
    func savedValuesAreStable() throws {
        var machine = try SavedStepValueModel.makeMachine()
        let result = try machine.send(.advance)
        #expect(result.after.count == 4)
        #expect(result.after.copied == 3)
        let graph = try ReachabilityGraph(
            initialMachines: SavedStepValueModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)

        let compilation = try SavedStepValueModel.spec.compile()
        let initial = try firstCompiledState(in: compilation)
        let next = try #require(try compiledSuccessors(
            named: "advance", arguments: [], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "count", in: next, compilation: compilation) == .int(4))
        #expect(try renderedValue(named: "copied", in: next, compilation: compilation) == .int(3))
    }

}

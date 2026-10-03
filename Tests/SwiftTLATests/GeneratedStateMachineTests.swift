@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedStateMachineTests {
    @Test("#spec bound builders execute in an external consumer")
    func specExpressionMacroCompilesExternally() throws {
        let build = try runExternalConsumer("SpecExpressionMacro")

        #expect(build.status == 0, Comment(rawValue: build.output))
    }

    @Test("@TLAModel generates a parameterized action")
    func modelParameterizedAction() throws {
        var machine = try SingleParameterActionMachine.makeMachine()
        _ = try machine.send(.select(choice: 1))
        #expect(machine.state.value == 1)
    }

    @Test("Generated actions retain every declared parameter")
    func generatedActionsRetainEveryDeclaredParameter() throws {
        var enabled = try ThreeParameterActionMachine.makeMachine()
        _ = try enabled.send(.transfer(source: 2, destination: 20, amount: 200))
        #expect(enabled.state.value == 1)
        #expect(ThreeParameterActionMachine.spec.actions[0].bindings.map(\.name) == [
            "source", "destination", "amount"
        ])

        var invalidMiddleParameter = try ThreeParameterActionMachine.makeMachine()
        let before = invalidMiddleParameter.state
        #expect(throws: GeneratedMachineError.self) {
            try invalidMiddleParameter.send(.transfer(source: 2, destination: 30, amount: 200))
        }
        #expect(invalidMiddleParameter.state.value == 0)
        #expect(invalidMiddleParameter.state == before)
    }

    @Test("Three-parameter actions preserve one contract across source, compilation, generated execution, and rendering")
    func threeParameterActionIsConsistentAcrossEveryExecutionPath() throws {
        let sourceText = """
        {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("transfer", parameters: [
                ActionParameter("source", values: [1, 2]),
                ActionParameter("destination", values: [10, 20]),
                ActionParameter("amount", values: [100, 200])
            ]) {
                value.becomes(source + destination + amount)
            }
        }
        """
        let closure = try #require(Parser.parse(source: sourceText).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
        let value = Var<Int>("value")
        let source = Expr<Int>(.variable("source"))
        let destination = Expr<Int>(.variable("destination"))
        let amount = Expr<Int>(.variable("amount"))
        let sourceSpecification = TLASpec("EndToEndThreeParameterActionMachine") {
            Variable(value, 0)
            Action("transfer", parameters: [
                ActionParameter("source", values: [1, 2]),
                ActionParameter("destination", values: [10, 20]),
                ActionParameter("amount", values: [100, 200])
            ]) {
                value.becomes(source + destination + amount)
            }
        }

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.count == 1)
        let parsedAction = try #require(parsed.actions.first)
        #expect(parsedAction.name == sourceSpecification.actions[0].name)
        #expect(parsedAction.body == sourceSpecification.actions[0].body)
        #expect(parsedAction.bindings == sourceSpecification.actions[0].bindings)
        #expect(EndToEndThreeParameterActionMachine.spec.actions == sourceSpecification.actions)

        let expectedArguments: [[TLAValue]] = [
            [.int(1), .int(10), .int(100)], [.int(1), .int(10), .int(200)],
            [.int(1), .int(20), .int(100)], [.int(1), .int(20), .int(200)],
            [.int(2), .int(10), .int(100)], [.int(2), .int(10), .int(200)],
            [.int(2), .int(20), .int(100)], [.int(2), .int(20), .int(200)]
        ]
        let compilation = try sourceSpecification.compile()
        let machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 100)
        let initialTransitions = try #require(graph.transitions[machine.snapshot])
        #expect(try initialTransitions.map { try machine.formalCall(for: $0.action).arguments } == expectedArguments)
        let initialActions = try machine.enabledActions()
        let expectedActions: [EndToEndThreeParameterActionMachine.Action] = [
            .transfer(source: 1, destination: 10, amount: 100), .transfer(source: 1, destination: 10, amount: 200),
            .transfer(source: 1, destination: 20, amount: 100), .transfer(source: 1, destination: 20, amount: 200),
            .transfer(source: 2, destination: 10, amount: 100), .transfer(source: 2, destination: 10, amount: 200),
            .transfer(source: 2, destination: 20, amount: 100), .transfer(source: 2, destination: 20, amount: 200)
        ]
        #expect(initialActions == expectedActions)
        #expect(initialTransitions.map(\.action) == expectedActions)
        #expect(try machine.isEnabled(.transfer(source: 2, destination: 20, amount: 200)))
        #expect(try machine.isEnabled(.transfer(source: 2, destination: 30, amount: 200)) == false)

        let renderedCalls = try compilation.render().actions
        #expect(renderedCalls.map(\.sourceName) == Array(repeating: "transfer", count: 8))
        #expect(renderedCalls.map(\.arguments) == expectedArguments)
        #expect(renderedCalls.map(\.renderedName) == [
            "transfer__0_0_0", "transfer__0_0_1", "transfer__0_1_0", "transfer__0_1_1",
            "transfer__1_0_0", "transfer__1_0_1", "transfer__1_1_0", "transfer__1_1_1"
        ])

        var generatedMachine = try EndToEndThreeParameterActionMachine.makeMachine()
        let before = generatedMachine.state
        let transition = try generatedMachine.send(.transfer(source: 2, destination: 20, amount: 200))
        #expect(transition.action == .transfer(source: 2, destination: 20, amount: 200))
        #expect(transition.after.value == 222)
        #expect(throws: GeneratedMachineError.self) {
            try generatedMachine.send(.transfer(source: 2, destination: 30, amount: 200))
        }
        #expect(generatedMachine.state.value == 222)
        #expect(before.value == 0)
    }

    @Test("Generated machine preserves typed actions, transitions, and state after rejection")
    func generatedMachineUsesCheckedThreeArgumentActions() throws {
        var machine = try ThreeParameterActionMachine.makeMachine()
        let action = ThreeParameterActionMachine.Action.transfer(source: 2, destination: 20, amount: 200)
        let transition = try machine.send(action)

        #expect(transition.action == action)
        #expect(transition.before.value == 0)
        #expect(transition.after.value == 1)

        let before = machine.state
        #expect(throws: GeneratedMachineError.self) {
            try machine.send(.transfer(source: 2, destination: 30, amount: 200))
        }
        #expect(machine.state == before)
    }

    @Test("Generated execution publishes complete parameterized transitions")
    func generatedExecutionPreservesParameterizedTransition() throws {
        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let before = machine.state

        let transition = try machine.send(.transfer(source: 2, destination: 20, amount: 200))
        let after = machine.state

        #expect(transition.action == .transfer(source: 2, destination: 20, amount: 200))
        #expect(transition.before.value == 0)
        #expect(transition.after.value == 222)
        #expect(before.value == 0)
        #expect(after.value == 222)
    }

    @Test("Actor returns the generated machine's three-argument transition")
    func actorMatchesGeneratedMachineThreeArgumentTransition() async throws {
        var machine = try ThreeParameterActionMachine.makeMachine()
        let expected = try machine.send(.transfer(source: 2, destination: 20, amount: 200))

        let actor = try ThreeParameterActionMachine.Actor()
        let acted = try await actor.send(.transfer(source: 2, destination: 20, amount: 200))

        #expect(acted.action == expected.action)
        #expect(acted.before.value == expected.before.value)
        #expect(acted.after.value == expected.after.value)
    }

    @Test("Rejected generated actions preserve machine and actor state")
    func rejectedActionsDoNotMutate() async throws {
        var machine = try ThreeParameterActionMachine.makeMachine()
        let machineBefore = machine.state
        do {
            _ = try machine.send(.transfer(source: 2, destination: 30, amount: 200))
            Issue.record("Expected rejected machine action")
        } catch {
            #expect(error is GeneratedMachineError)
        }
        #expect(machine.state == machineBefore)

        let actor = try ThreeParameterActionMachine.Actor()
        let actorBefore = await actor.state
        await #expect(throws: GeneratedMachineError.self) {
            try await actor.send(.transfer(source: 2, destination: 30, amount: 200))
        }
        #expect(await actor.state == actorBefore)
    }

    @Test("Fixed-arity action syntax does not type check")
    func fixedArityActionSyntaxDoesNotCompile() throws {
        let build = try buildExternalConsumer("InvalidActionParameterAPI")

        #expect(build.status != 0)
        #expect(build.output.contains("Parameterized action 'singleParameter' requires a parameters list"))
        #expect(build.output.contains("Parameterized action 'multipleParameters' requires a parameters list"))
        #expect(build.output.contains("Parameterized action 'idParameter' requires a parameters list"))
        #expect(build.output.contains("Parameterized action 'namedParameters' requires a parameters list"))
        #expect(build.output.contains("value of type 'NamedAction' has no member 'binding'"))
        #expect(build.output.contains("value of type 'ActionDecl' has no member 'binding'"))
        #expect(build.output.contains("incorrect argument label in call (have 'name:body:binding:', expected 'name:body:bindings:')"))
    }

    @Test("Algorithm initialization produces the expected generated and explored states")
    func generatedAlgorithmInitialState() throws {
        var machine = try GeneratedAlgorithmMachine.makeMachine()
        #expect(machine.state.count == 1)
        #expect(try machine.send(.tick).after.count == 2)
        let graph = try ReachabilityGraph(initialMachines: GeneratedAlgorithmMachine.initialMachines(), maximumStates: 100)
        #expect(graph.initialStates.count == 1)
        #expect(graph.transitions.count == 2)
        #expect(graph.safetyViolations.isEmpty)
    }

}

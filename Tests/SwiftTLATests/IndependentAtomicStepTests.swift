import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IndependentAtomicStepTests {
    private var sourceTypes: SourceTypeMetadata {
        .init(enums: [parserTestEnum("Step", cases: ["next": .string("next"), "other": .string("other")])])
    }

    @Test("top-level steps preserve ordered writes without generated control state")
    func independentExecution() throws {
        let source = IndependentAtomicSteps.spec
        #expect(source.sourceAlgorithms.isEmpty)
        #expect(source.sourceAtomicSteps.count == 5)
        let compilation = try source.compile()
        #expect(compilation.layout.variables.map(\.declaration.name) == ["value", "copied"])
        #expect(compilation.layout.actions.map(\.declaration.name) == ["advance", "reset", "choose", "blocked", "rollback"])
        var machine = try IndependentAtomicSteps.makeMachine()
        #expect(try !machine.isEnabled(.reset))
        #expect(try !machine.isEnabled(.blocked))
        #expect(try !machine.isEnabled(.rollback))
        _ = try machine.send(.advance)
        #expect(machine.state.value == 1 && machine.state.copied == 1)
        _ = try machine.send(.advance)
        #expect(machine.state.value == 2 && machine.state.copied == 2)
        #expect(try !machine.isEnabled(.advance))
        _ = try machine.send(.reset)
        #expect(machine.state.value == 0 && machine.state.copied == 0)
    }

    @Test("native exploration retains all choices, guards, and compiler-owned assertions")
    func completeScenario() throws {
        let scenario = try #require(try IndependentAtomicSteps.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 20)
        try run.validateExpectations()
        let graph = try scenario.explore(maximumStates: 20)
        #expect(graph.transitions.count == 3)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 5)
        let initial = try #require(graph.initialStates.first)
        let choices = graph.transitions[initial, default: []].filter { $0.action == .choose }
        #expect(Set(choices.map { $0.target.state.value }) == [1, 2])
        #expect(graph.safetyViolations.isEmpty)
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("__step_assert_advance_0"))
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        let compilation = try IndependentAtomicSteps.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let expectedModule = try program.renderModule().renderedModuleSource
        #expect(expectedModule == rendered.tlaBundle.tla)
    }

    @Test("independent steps reject algorithm control transfers at their source", arguments: [
        "Goto(Step.next)", "Stop()", "Return()",
        "If(true) { Stop() }", "With(IntRange(0, through: 1)) { item in Stop() }"
    ])
    func rejectsControlTransfer(_ body: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.next) { \(body) }
        }
        """), sourceTypes: sourceTypes)
        #expect(!spec.diagnostics.isEmpty)
        #expect(spec.diagnostics.contains { $0.description.contains("require an enclosing Algorithm") })
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("independent steps reject malformed guards, duplicate labels, and mixed scheduling", arguments: [
        "Do(Step.next, unless: true) { Skip() }",
        "Do(Step.next, when: 1) { Skip() }",
        "Do(Step.next) { Skip() }\nDo(Step.next) { Skip() }",
        "Do(Step.next) { Skip() }\nAlgorithm(\"Mixed\") { Do(Step.other) { Stop() } }"
    ])
    func rejectsInvalidSteps(_ steps: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            \(steps)
        }
        """), sourceTypes: sourceTypes)
        #expect(throws: (any Error).self) {
            let compilation = try spec.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }
}

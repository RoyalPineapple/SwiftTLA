import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IndependentAtomicStepTests {
    private var sourceTypes: SourceTypeMetadata {
        .init(enums: [parserTestEnum("Step", cases: ["next": .string("next"), "other": .string("other")])])
    }

    @Test("specification statement macros expand in ordinary and parameterized independent steps")
    func expandsSpecificationMacros() throws {
        let spec = SpecParser.parseSpecClosure(named: "SharedMacro", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            let advance = Macro { Assign(value, to: value + 1) }
            Do(Step.next) { advance(); advance() }
            Do(Step.other, over: Set<Int>([1, 2])) { amount in
                advance()
                Assign(value, to: value + amount)
            }
        }
        """), sourceTypes: sourceTypes)
        #expect(spec.diagnostics.isEmpty)
        #expect(spec.sourceAlgorithms.isEmpty)
        #expect(spec.sourceAtomicSteps.count == 2)
        let compilation = try spec.compile()
        #expect(compilation.layout.variables.map(\.declaration.name) == ["value"])
        let initial = try firstCompiledState(in: compilation)
        let next = try #require(try compiledSuccessors(named: "next", arguments: [], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "value", in: next, compilation: compilation) == .int(2))
        let other = try #require(try compiledSuccessors(named: "other", arguments: [.int(2)], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "value", in: other, compilation: compilation) == .int(3))
    }

    @Test("specification statement macros reject mutable declarations, duplicates, and independent control transfers", arguments: [
        "var advance = Macro { Assign(value, to: 1) }\nDo(Step.next) { advance() }",
        "let advance = Macro { Skip() }\nlet advance = Macro { Skip() }",
        "let advance = Macro { Stop() }\nDo(Step.next) { advance() }"
    ])
    func rejectsInvalidSpecificationMacros(_ declarations: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "InvalidMacro", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            \(declarations)
        }
        """), sourceTypes: sourceTypes)
        #expect(!spec.diagnostics.isEmpty)
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("algorithms inherit specification macros and can shadow them locally", arguments: [false, true])
    func inheritsAndShadowsSpecificationMacros(shadow: Bool) throws {
        let local = shadow ? "let advance = Macro { Assign(value, to: value + 2) }" : ""
        let spec = SpecParser.parseSpecClosure(named: "MacroScope", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            let advance = Macro { Assign(value, to: value + 1) }
            Algorithm("Nested") {
                \(local)
                Do(Step.next) { advance() }
            }
        }
        """), sourceTypes: sourceTypes)
        #expect(spec.diagnostics.isEmpty)
        let compilation = try spec.compile()
        let initial = try firstCompiledState(in: compilation)
        let next = try #require(try compiledSuccessors(named: "next", arguments: [], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "value", in: next, compilation: compilation) == .int(shadow ? 2 : 1))
    }

    @Test("bound steps reject mutable bindings, duplicate registration, and unregistered enabledness", arguments: [
        "var next = Do(Step.next) { Skip() }\nnext",
        "let next = Do(Step.next) { Skip() }\nnext\nnext",
        "let next = Do(Step.next) { Skip() }\nInvariant(\"Ready\") { next.enabled }"
    ])
    func rejectsInvalidBoundSteps(_ declarations: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "InvalidBoundSteps", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            \(declarations)
        }
        """), sourceTypes: sourceTypes)
        #expect(throws: (any Error).self) { try spec.compile() }
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

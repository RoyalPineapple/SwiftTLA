import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ParameterizedAtomicStepTests {
    @Test("independent action arguments preserve typed dispatch and ordered assignments")
    func dispatchesTypedArguments() throws {
        var machine = try ParameterizedAtomicSteps.makeMachine(configuration: .init(members: [0, 1]))
        #expect(try !machine.isEnabled(.transfer(source: 1, destination: 0)))
        #expect(try !machine.isEnabled(.select(member: 2)))
        _ = try machine.send(.select(member: 1))
        #expect(machine.state.value == 1 && machine.state.copied == 1)
        _ = try machine.send(.transfer(source: 1, destination: 0))
        #expect(machine.state.value == 0 && machine.state.copied == 0)
    }

    @Test("configured domains retain all argument-labeled edges and default deadlock checks")
    func exploresConfiguredDomains() throws {
        let scenarios = try ParameterizedAtomicSteps.validationScenarios()
        #expect(scenarios.count == 3)
        for (index, scenario) in scenarios.enumerated() {
            let run = try NativeScenarioRun(scenario, maximumStates: 10)
            try run.validateExpectations()
            #expect(run.coverage.coversCompleteScenario)
            #expect(run.native.graph.graph.states.count == [1, 1, 2][index])
            #expect(run.native.graph.graph.edges.count == [0, 1, 6][index])
            #expect(run.native.checks.properties.values.allSatisfy { $0 == .satisfied })
            let rendered = try scenario.render()
            #expect(rendered.actions.count == [0, 2, 6][index])
            #expect(!rendered.tlaBundle.tla.contains("VARIABLES pc"))
            #expect(rendered.tlaBundle.tla.contains("select(member)"))
            #expect(rendered.tlaBundle.tla.contains("transfer(source, destination)"))
            let compilation = try ParameterizedAtomicSteps.spec.compile()
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
            let builderSource = try program.renderModule().renderedModuleSource
            let generatedSource = rendered.tlaBundle.tla
            let differences = zip(builderSource.split(separator: "\n"), generatedSource.split(separator: "\n"))
                .filter { $0 != $1 }.map { "builder: \($0)\ngenerated: \($1)" }.joined(separator: "\n")
            #expect(builderSource == generatedSource, "\(differences)")
        }
    }

    @Test("parameterized steps reject malformed domains, bindings, and scheduled placement", arguments: [
        "Do(Step.select, over: 1) { member in Skip() }",
        "Do(Step.select, over: Set<Int>([0])) { Skip() }",
        "Do(Step.select, over: Set<Int>([0])) { _ in Skip() }",
        "Do(Step.select, over: Set<Int>([0]), Set<Int>([1])) { member, member in Skip() }",
        "Do(Step.select, over: Set<Int>([0])) { first, second in Skip() }",
        "Do(Step.select, over: selected) { member in Skip() }",
        "Do(Step.select, over: []) { member in Skip() }",
        "Do(Step.select, over: Set<Int>([0])) { member in Stop() }",
        "Algorithm(\"Scheduled\") { Do(Step.select, over: Set<Int>([0])) { member in Skip() } }"
    ])
    func rejectsInvalidBindings(_ body: String) throws {
        let source = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        { scope in
            let selected = scope.sharedVar(initial: Set<Int>([0]))
            \(body)
        }
        """), sourceTypes: .init(enums: [parserTestEnum("Step", cases: ["select": .string("select")])]))
        #expect(throws: (any Error).self) {
            let compilation = try source.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }
}

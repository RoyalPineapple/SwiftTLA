import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ScopedReachabilityTests {
    @Test("scoped reachability requires one coherent all-member witness")
    func checksOneState() throws {
        let scenarios = try ScopedReachabilityClaims.validationScenarios()
        let graph = try scenarios[0].explore(maximumStates: 20)
        #expect(graph.reachabilityResults[.AllOwn] == .unreachable)
        guard case .reached(let state) = graph.reachabilityResults[.AllVisited] else {
            Issue.record("Expected a shared execution visiting both members")
            return
        }
        let trace = try graph.trace(to: state)
        #expect(trace.count == 3)
        #expect(Set(trace.dropFirst().map { $0.state.state.owner }) == [0, 1])
        for scenario in scenarios {
            let run = try NativeScenarioRun(scenario, maximumStates: 20)
            try run.validateExpectations()
            let rendered = try scenario.render()
            #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
            #expect(rendered.tlaBundle.tla.contains("AllOwn == ~("))
            #expect(rendered.tlaBundle.tla.contains("AllOwn == ~((\\A _process \\in members : (owner = _process)))"))
            #expect(rendered.tlaBundle.tla.contains("AllVisited == ~((\\A _process \\in members : visited[_process]))"))
            #expect(rendered.reachabilityNames == (scenario.name == "Selected"
                ? ["AllVisited"] : ["AllOwn", "AllVisited", "EitherOwns", "Initial"]))
        }
        let selected = try scenarios[2].explore(maximumStates: 20)
        #expect(try NativeScenarioRun(scenarios[2], maximumStates: 20).native.graph
            == NativeScenarioRun(scenarios[0], maximumStates: 20).native.graph)
        #expect(Set(selected.reachabilityResults.keys) == [.AllVisited])
        let empty = try scenarios[1].explore(maximumStates: 20)
        for result in empty.reachabilityResults.values {
            guard case .reached(let witness) = result else {
                Issue.record("An empty population has a vacuously true state predicate")
                continue
            }
            #expect(try empty.trace(to: witness).count == 1)
        }
        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try scenarios[0].explore(maximumStates: 1)
        }
    }

    @Test("missing, duplicate, bare, and non-Boolean definitions fail compilation", arguments: 0..<4)
    func rejectsInvalidDefinition(variant: Int) throws {
        let definition = ["", "goal { true }\ngoal { false }", "goal", "goal { 1 }"][variant]
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        {
            let goal = Reachable()
            \(definition)
            Validation("Check") {}.expect(goal, .satisfied)
        }
        """))
        #expect(throws: (any Error).self) {
            let compiled = try spec.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        }
    }

    @Test("direct builders retain reachability identity through sequential lowering")
    func retainsIdentity() throws {
        let goal = Reachable(_name: "Goal")
        let predicate = goal { true }
        #expect(predicate.reference == goal.reference)
        let spec = TLASpec("Sequential") {
            Algorithm("Worker") {
                Do(ScopedReachabilityClaims.Step.visit) { Skip() }
                predicate
            }
            Validation("Check") {}.checking(only: [goal])
        }
        let compiled = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.reachabilityProperties.map(\.name) == ["Goal"])
        #expect(program.behavior.validationScenarios.count == 1)
    }

    @Test("equal names cannot substitute a foreign reachability handle")
    func rejectsForeignIdentity() throws {
        let own = Reachable(_name: "Goal")
        let foreign = Reachable(_name: "Goal")
        let spec = TLASpec("Foreign") {
            own { true }
            Validation("Check") {}.expect(foreign, .satisfied)
        }
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("Swift rejects non-Boolean reachability predicates and bare handles")
    func rejectsInvalidSwiftUsage() throws {
        let build = try buildExternalConsumer("InvalidModelProperty")
        #expect(build.status != 0)
        let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
        for line in [36, 37] {
            #expect(errors.contains { $0.contains("InvalidModelProperty.swift:\(line):") },
                "Missing reachability rejection: \(errors.joined(separator: "\n"))")
        }
    }
}

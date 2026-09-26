import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ScopedTemporalTests {
    @Test("all temporal handle kinds retain scope and their typed property identity")
    func checksAllKinds() throws {
        let scenario = try #require(try ScopedTemporalClaims.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 20)
        try run.validateExpectations()
        let graph = try scenario.explore(maximumStates: 20)
        #expect(Set(graph.temporalResults.keys) == [.Bounded, .Started, .Recurs, .Settles, .Responds])
        #expect(graph.temporalResults.values.allSatisfy { $0.status == .satisfied })
        let rendered = try scenario.render()
        #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
        #expect(rendered.tlaBundle.tla.contains("Recurs == (\\A _process \\in members: []<>(value = _process))"))
        #expect(rendered.tlaBundle.tla.contains("Settles == (\\A _process \\in members: <>[]visited[_process])"))
    }

    @Test("outer expectations retain an inner member's actionable counterexample")
    func checksExpectedFailure() throws {
        let scenario = try #require(try RecurringPopulation.validationScenarios().first { $0.name == "Outside cycle" })
        let run = try NativeScenarioRun(scenario, maximumStates: 20)
        try run.validateExpectations()
        #expect(scenario.expectations[.EachRecurs] == .violated)
        #expect(scenario.expectations[.EachVisits] == .satisfied)
        guard case .violated(let trace) = run.native.checks.properties["EachRecurs"] else {
            Issue.record("Expected the scoped temporal counterexample")
            return
        }
        try trace.validate(in: #require(run.native.graph).graph)
        #expect(trace.cycleStartIndex != nil)
    }

    @Test("unregistered, repeated, bare, and malformed temporal definitions fail compilation", arguments: 0..<5)
    func rejectsInvalidDefinition(variant: Int) throws {
        let definition = ["", "claim(true)\nclaim(false)", "claim", "claim(true, false)", "claim(1)"][variant]
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        {
            let claim = Eventually()
            \(definition)
            Validation("Check") {}.expect(claim, .satisfied)
        }
        """))
        #expect(throws: (any Error).self) {
            let compiled = try spec.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        }
    }

    @Test("Swift rejects temporal arity, predicate types, and undefined builder components")
    func rejectsInvalidSwiftUsage() throws {
        let build = try buildExternalConsumer("InvalidModelProperty")
        #expect(build.status != 0)
        let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
        for line in [30, 31, 32, 33] {
            #expect(errors.contains { $0.contains("InvalidModelProperty.swift:\(line):") },
                "Missing temporal handle rejection: \(errors.joined(separator: "\n"))")
        }
    }
}

import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct DictionaryConfigurationTests {
    @Test("dictionary bindings preserve typed configuration, generated state, and complete graphs")
    func validatesDictionaryScenarios() throws {
        let scenarios = try ConfiguredDictionaryValues.validationScenarios()
        #expect(scenarios.count == 4)
        for (index, scenario) in scenarios.enumerated() {
            let run = try NativeScenarioRun(scenario, maximumStates: 10)
            try run.validateExpectations()
            #expect(run.coverage.coversCompleteScenario)
            #expect(run.native.graph.graph.states.count == 1)
            #expect(run.native.graph.graph.edges.count == [0, 0, 1, 2][index])
            #expect(run.native.checks.properties["total"] == .satisfied)
            #expect(run.native.checks.properties["sameKey"] == .satisfied)
            #expect(run.native.checks.properties["hasCapacity"] == .satisfied)
            let bundle = try scenario.render().tlaBundle
            #expect(bundle.cfg.contains("CONSTANT capacity <- __SwiftTLAParameter1"))
            #expect(bundle.tla.contains("__SwiftTLAParameter1 == ["))
        }
        let configuration = try ConfiguredDictionaryValues.Configuration(
            jugs: ["small", "big"], capacity: ["small": 3, "big": 5])
        var machine = try ConfiguredDictionaryValues.makeMachine(configuration: configuration)
        #expect(machine.state.contents == configuration.capacity)
        _ = try machine.send(.fill(jug: "small"))
        #expect(machine.state.contents == ["small": 3, "big": 5])
    }

    @Test("dictionary configuration rejects missing keys, extra keys, and invalid values", arguments: [
        ["small": 3], ["small": 3, "big": 5, "extra": 3], ["small": 3, "big": 4]
    ])
    func rejectsInvalidFunctions(_ capacity: [String: Int]) {
        #expect(throws: (any Error).self) {
            try ConfiguredDictionaryValues.Configuration(jugs: ["small", "big"], capacity: capacity)
        }
    }

    @Test("dictionary bindings reject duplicate keys, incompatible values, and parameter dependencies", arguments: [
        "[\"small\": 3, \"small\": 5]", "[\"small\": true]", "capacity"
    ])
    func rejectsInvalidLiterals(_ value: String) throws {
        let source = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        { scope in
            let capacity = scope.parameter(as: [String: Int].self,
                in: Functions(from: Set<String>(["small"]), to: Set<Int>([3, 5])))
            let count = scope.sharedVar(initial: 0)
            Validation("Invalid") { Bind(capacity, to: \(value)) }
        }
        """))
        #expect(throws: (any Error).self) {
            let compilation = try source.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }
}

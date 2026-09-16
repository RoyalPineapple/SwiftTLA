import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ValidationScenarioTests {
    @Test("model-owned scenarios derive configuration, complete exploration, and symbolic export")
    func derivesCounterRuns() throws {
        let scenarios = try ConfiguredCounter.validationScenarios()
        #expect(scenarios.map(\.name) == ["Completes at two", "Deadlocks at four"])
        #expect(scenarios.map { $0.configuration.limit } == [2, 4])
        #expect(try scenarios[0].render().tlaBundle.tla == scenarios[1].render().tlaBundle.tla)
        for scenario in scenarios {
            let graph: ReachabilityGraph<ConfiguredCounter> = try scenario.explore(maximumStates: 10)
            #expect(Set(scenario.expectations.keys) == Set(ConfiguredCounter.Property.allCases))
            #expect(scenario.expectations.values.allSatisfy { $0 == .satisfied })
            #expect(graph.transitions.count == scenario.configuration.limit + 1)
            let rendered = try scenario.render()
            #expect(rendered.checkNames == Set(scenario.expectations.keys.map { ConfiguredCounter.formalPropertyNames[$0]! }))
            #expect(rendered.checksDeadlock)
            #expect(graph.deadlockedStates.isEmpty == scenario.configuration.stopAtLimit)
            #expect(scenario.deadlockExpectation == (scenario.configuration.stopAtLimit ? .satisfied : .violated))
            guard case .reached(let witness) = graph.reachabilityResults[.AtLimit] else {
                Issue.record("Missing scenario reachability witness")
                continue
            }
            #expect(try graph.trace(to: witness).count == scenario.configuration.limit + 1)
        }
    }

    @Test("expectations change verdict metadata without changing model predicates")
    func retainsPositiveMeaning() throws {
        let scenario = try #require(ScenarioExpectations.validationScenarios().first)
        #expect(scenario.expectations == [.Bounded: .satisfied, .BeyondLimit: .violated])
        let graph = try scenario.explore(maximumStates: 3)
        #expect(graph.reachabilityResults[.BeyondLimit] == .unreachable)
        #expect(graph.transitions.count == 3)
        #expect(try scenario.render().tlaBundle.tla.contains("BeyondLimit == ~("))
        let compiled = try ScenarioExpectations.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let binding = try #require(program.behavior.validationScenarios.first?.bindings.values.first)
        #expect(binding.resultType == .int)
        #expect(binding.operation == .value(.integer(2)))
    }

    @Test("scenario bindings reject missing, duplicate, and foreign parameters", arguments: [0, 1, 2])
    func rejectsInvalidBindings(variant: Int) throws {
        var spec = ConfiguredCounter.spec
        let original = try #require(spec.validationScenarios.first)
        var bindings = original.bindings
        switch variant {
        case 0: bindings.removeLast()
        case 1: bindings.append(bindings[0])
        default: bindings[0] = .init(parameter: .init(name: "limit"), value: .value(.int(2)))
        }
        spec.validationScenarios = [.init(name: original.name, bindings: bindings)]
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }

    @Test("scenario expectations require registered property identity and reject duplicate overrides")
    func rejectsInvalidExpectations() throws {
        for foreign in [false, true] {
            var spec = ScenarioExpectations.spec
            var scenario = try #require(spec.validationScenarios.first)
            let expectation = try #require(scenario.expectations.first)
            if foreign {
                scenario.expectations = [(.init(name: expectation.property.name), .violated)]
            } else { scenario.expectations.append(expectation) }
            spec.validationScenarios = [scenario]
            #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("scenario identity includes bindings and expected outcomes")
    func preservesScenarioIdentity() throws {
        let original = ScenarioExpectations.spec
        var changed = original
        changed.validationScenarios[0].deadlockExpectations = [.satisfied]
        #expect(try original.compile().identity != changed.compile().identity)
    }

    @Test("expectations follow declaration handles after names change")
    func resolvesHandlesWithoutNames() throws {
        var spec = ScenarioExpectations.spec
        let invariant = try #require(spec.invariants.first)
        let reachable = try #require(spec.reachabilityProperties.first)
        let temporal = Always("OriginalTemporal", true)
        spec.invariants[0] = .init(name: "RenamedInvariant", body: invariant.body, reference: invariant.reference)
        spec.reachabilityProperties[0] = .init(name: "RenamedReachable", body: reachable.body, reference: reachable.reference)
        spec.temporalProperties.append(.init(name: "RenamedTemporal", expr: temporal.expr, bindings: [], reference: temporal.reference))
        spec.validationScenarios[0].expectations = [
            (try #require(invariant.reference), .violated),
            (try #require(reachable.reference), .satisfied),
            (temporal.reference, .violated)
        ]
        let compiled = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let scenario = try #require(program.behavior.validationScenarios.first)
        #expect(scenario.expectations[try #require(program.behavior.invariants.first).id] == .violated)
        #expect(scenario.expectations[try #require(program.behavior.reachabilityProperties.first).id] == .satisfied)
        #expect(scenario.expectations[try #require(program.behavior.temporalProperties.first).id] == .violated)
    }

    @Test("replacing a registered declaration with a namesake rejects its old handle")
    func rejectsDetachedHandle() throws {
        var spec = ScenarioExpectations.spec
        let property = try #require(spec.reachabilityProperties.first)
        spec.reachabilityProperties[0] = .init(name: property.name, body: property.body,
            reference: .init(name: property.name))
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }

    @Test("compilation identity encodes resolved expectation targets, not handle labels or UUIDs")
    func fingerprintsResolvedTargets() throws {
        let original = ScenarioExpectations.spec
        #expect(try original.compile().identity == ScenarioExpectations.spec.compile().identity)
        var changed = original
        let invariant = try #require(original.invariants.first)
        let reachable = try #require(original.reachabilityProperties.first)
        changed.invariants[0] = .init(name: invariant.name, body: invariant.body, reference: reachable.reference)
        changed.reachabilityProperties[0] = .init(name: reachable.name, body: reachable.body, reference: invariant.reference)
        #expect(try original.compile().identity != changed.compile().identity)
    }
}

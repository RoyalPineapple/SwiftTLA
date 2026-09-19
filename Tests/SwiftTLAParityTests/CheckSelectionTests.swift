import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct CheckSelectionTests {
    @Test("selected checks preserve the complete graph and report omitted claims")
    func preservesGraph() throws {
        let scenarios = try SelectedChecksModel.validationScenarios()
        let runs = try scenarios.map { try NativeScenarioRun($0, maximumStates: 2) }
        for run in runs { try run.validateExpectations() }
        #expect(runs.allSatisfy { $0.native.graph == runs[0].native.graph })
        #expect(runs[0].native.graph.graph.states.count == 2)
        #expect(runs[0].coverage.coversCompleteScenario)
        #expect(!runs[1].coverage.coversCompleteScenario)
        #expect(runs[1].coverage.selectedProperties == ["Reached", "Safe"])
        #expect(runs[1].coverage.omittedProperties == ["InitiallyZero", "StaysZero"])
        #expect(runs[1].native.checks.deadlock == nil)
        #expect(Set(runs[1].native.checks.properties.keys) == ["Reached", "Safe"])
        #expect(runs[2].native.checks.properties.isEmpty)
        #expect(runs[2].native.checks.deadlock == nil)
        for scenario in scenarios {
            let graph = try scenario.explore(maximumStates: 2)
            #expect(graph.deadlockedStates.count == 1)
            #expect(throws: ExplorationError.stateLimitExceeded(1)) { try scenario.explore(maximumStates: 1) }
        }
    }

    @Test("native and direct or PlusCal exports share the selected check configuration")
    func exportsSelection() throws {
        let scenario = try #require(SelectedChecksModel.validationScenarios().dropFirst().first)
        let rendered = try scenario.render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.contains("CHECK_DEADLOCK FALSE"))
        #expect(cfg.contains("INVARIANT Safe"))
        #expect(cfg.contains("INVARIANT Reached"))
        #expect(!cfg.contains("INVARIANT InitiallyZero"))
        #expect(!cfg.contains("PROPERTY StaysZero"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
        #expect(rendered.tlaBundle.tla == (try SelectedChecksModel.render()).tlaBundle.tla)
        #expect(scenario.checking.properties == [.Safe, .Reached])
        #expect(scenario.expectations == [.Safe: .satisfied, .Reached: .satisfied])
    }

    @Test("unselected predicates are not evaluated")
    func skipsUndefinedPredicates() throws {
        let scenario = try #require(UnselectedPredicateModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 1)
        #expect(graph.transitions.count == 1)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.reachabilityResults.isEmpty)
        #expect(graph.temporalResults.isEmpty)
        let machines = try scenario.initialMachines()
        for property in UnselectedPredicateModel.Property.allCases {
            #expect(throws: (any Error).self) {
                try ReachabilityGraph(initialMachines: machines, maximumStates: 1,
                    checking: ModelChecks(properties: [property], checkDeadlock: false))
            }
        }
    }

    @Test("invalid selection and expectations for disabled checks fail compilation", arguments: 0..<6)
    func rejectsInvalidSelection(variant: Int) throws {
        var spec = SelectedChecksModel.spec
        var scenario = try #require(spec.validationScenarios[1...].first)
        let selected = try #require(scenario.propertySelections.first)
        switch variant {
        case 0: scenario.propertySelections.append(selected)
        case 1: scenario.deadlockSelections.append(true)
        case 2: scenario.propertySelections = [selected + [selected[0]]]
        case 3: scenario.propertySelections = [[.init(name: "Safe")]]
        case 4: scenario.deadlockExpectations = [.violated]
        default: scenario.expectations = [(try #require(spec.invariants[1].reference), .violated)]
        }
        spec.validationScenarios = [scenario]
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }

    @Test("selection contributes to compilation identity")
    func fingerprintsSelection() throws {
        let original = SelectedChecksModel.spec
        var changed = original
        changed.validationScenarios[1].propertySelections = [[]]
        #expect(try original.compile().identity != changed.compile().identity)
        changed = original
        changed.validationScenarios[1].deadlockSelections = [true]
        #expect(try original.compile().identity != changed.compile().identity)
    }
}

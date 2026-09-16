import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct BehaviorSelectionTests {
    @Test("INIT/NEXT omits weak specification fairness without changing the full graph")
    func selectsWeaklyFairBehavior() throws {
        let scenarios = try WeaklyFairConfiguredProcessMachine.validationScenarios()
        try compare(scenarios[1], scenarios[3])
    }

    @Test("INIT/NEXT omits strong specification fairness without changing the full graph")
    func selectsStronglyFairBehavior() throws {
        let scenarios = try StronglyFairConfiguredProcessMachine.validationScenarios()
        try compare(scenarios[1], scenarios[3])
    }

    private func compare<Scenario: ModelValidationScenario>(_ specification: Scenario, _ initialAndNext: Scenario) throws {
        #expect(specification.behavior == .specification)
        #expect(initialAndNext.behavior == .initialAndNext)
        let fair = try NativeScenarioRun(specification, maximumStates: 2)
        let unconstrained = try NativeScenarioRun(initialAndNext, maximumStates: 2)
        try fair.validateExpectations()
        try unconstrained.validateExpectations()
        #expect(fair.native.graph == unconstrained.native.graph)
        #expect(fair.native.graph.graph.states.count == 2)
        #expect(fair.native.checks.properties["AllVisited"] == .satisfied)
        guard case .violated(let witness) = unconstrained.native.checks.properties["AllVisited"] else {
            Issue.record("Expected an unfair stuttering witness")
            return
        }
        #expect(witness.cycleStartIndex != nil)
        try witness.validate(in: unconstrained.native.graph.graph)
        #expect(unconstrained.coverage.behavior == .initialAndNext)
        #expect(!unconstrained.coverage.coversCompleteScenario)
        let rendered = try initialAndNext.render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.hasPrefix("INIT Init\nNEXT Next\n"))
        #expect(!cfg.contains("SPECIFICATION"))
        #expect(cfg.contains("PROPERTY AllVisited"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
        #expect(rendered.tlaBundle.tla == (try specification.render()).tlaBundle.tla)
        let pass = try rendered.tlaBundle(checking: ["AllVisited"], checkDeadlock: false)
        #expect(pass.cfg.hasPrefix("INIT Init\nNEXT Next\n"))
        let defaultGraph = try ReachabilityGraph(initialMachines: initialAndNext.initialMachines(), maximumStates: 2)
        #expect(throws: EvidenceFormatError.self) { try NativeModelRun(defaultGraph, rendered: rendered) }
    }

    @Test("duplicate behavior selections fail and selection affects compilation identity")
    func validatesBehaviorDeclaration() throws {
        let original = WeaklyFairConfiguredProcessMachine.spec
        var duplicate = original
        duplicate.validationScenarios[3].behaviorSelections.append(.specification)
        #expect(throws: CompilationDiagnostic.self) { try duplicate.compile() }
        var changed = original
        changed.validationScenarios[3].behaviorSelections = [.specification]
        #expect(try original.compile().identity != changed.compile().identity)
    }
}

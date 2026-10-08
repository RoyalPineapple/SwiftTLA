import Testing
@testable import SwiftTLA

@Suite("Action-constrained checking")
struct ActionConstraintCheckingTests {
    @Test("The generated machine keeps executable successors while both native checkers exclude transitions")
    func filtersExplorationWithoutChangingExecution() throws {
        var application = try ActionConstrainedCounter.makeMachine()
        #expect(application.state.count == 0)
        _ = try application.send(.advance)
        _ = try application.send(.advance)
        #expect(application.state.count == 2)

        let initial = try ActionConstrainedCounter.makeMachine()
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 4,
            checking: .init(properties: [], checkDeadlock: true))
        #expect(Set(graph.transitions.keys.map { $0.state.count }) == [0, 1])
        #expect(graph.transitions.values.flatMap { $0 }.count == 1)
        #expect(graph.deadlockedStates.isEmpty)

        let result = try MachineValidator.run(initialMachines: [initial], maximumStates: 4,
            checking: .init(properties: [], checkDeadlock: true), stopOnViolation: false) { _ in }
        #expect(result.states == 2)
        #expect(result.edges == 1)
        #expect(!result.deadlockFound)
        if case .exhausted = result.completion {} else { Issue.record("Native checking stopped early") }
    }

    @Test("The generated TLA and TLC configuration carry the same transition bound")
    func rendersFormalActionConstraint() throws {
        let compilation = try ActionConstrainedCounter.spec.compile()
        #expect(compilation.description.actionConstraint == "ActionConstraint")
        let bundle = try compilation.render().plusCalBundle()
        #expect(bundle.root.tla.contains("ActionConstraint =="))
        #expect(bundle.cfg.contains("ACTION_CONSTRAINT ActionConstraint"))
    }

    @Test("An excluded successor does not become a sampled deadlock")
    func samplingStopsInconclusivelyAtConstraintBoundary() throws {
        let initial = try ActionConstrainedCounter.makeMachine()
        var generator = SystemRandomNumberGenerator()
        let result = try MachineSimulator.run(initialMachines: [initial], maximumDepth: 3,
            checking: .init(properties: [], checkDeadlock: true), using: &generator)
        guard case .inconclusive(let trace, .deadEnd) = result else {
            Issue.record("A transition excluded by ACTION_CONSTRAINT is not a deadlock")
            return
        }
        #expect(trace.map { $0.state.state.count } == [0, 1])
    }

    @Test("Action constraints share the checker run context without affecting application execution")
    func preservesRunOwnedCheckingEffects() throws {
        let initial = try ActionConstrainedRegisterCounter.makeMachine()
        var context = CheckingContext(registers: try initial.initialCheckingRegisters())
        try context.advanceLevel()
        let first = try #require(initial.successors(checking: &context).first?.machine)
        #expect(try initial.satisfiesActionConstraint(to: first, checking: &context))
        #expect(context.registers.inspections == 1)
        let second = try #require(first.successors(checking: &context).first?.machine)
        #expect(try !first.satisfiesActionConstraint(to: second, checking: &context))
        #expect(context.registers.inspections == 2)

        var application = initial
        _ = try application.send(.advance)
        #expect(application.state.count == 1)
        let bundle = try ActionConstrainedRegisterCounter.spec.compile().render().plusCalBundle()
        #expect(bundle.root.tla.contains("TLCSet"))
        #expect(bundle.cfg.contains("ACTION_CONSTRAINT ActionConstraint"))
    }

    @Test("An excluded transition still reports the invariant failure at its complete boundary state")
    func checksExcludedBoundaryState() throws {
        let initial = try ActionConstrainedCounter.makeMachine()
        let selected = ModelChecks<ActionConstrainedCounter.Property>(properties: [.BelowTwo], checkDeadlock: true)
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 4, checking: selected)
        let boundary = try #require(graph.safetyViolations.keys.first)
        #expect(boundary.state.count == 2)
        #expect(graph.safetyViolations[boundary] == [.invariant(.BelowTwo)])
        #expect(graph.transitions[boundary] == nil)
        #expect(try graph.trace(to: boundary).map { $0.state.state.count } == [0, 1, 2])

        let result = try MachineValidator.run(initialMachines: [initial], maximumStates: 4,
            checking: selected, stopOnViolation: false) { _ in }
        #expect(result.states == 2)
        #expect(result.edges == 1)
        #expect(result.violatedInvariants == [.BelowTwo])
    }

    @Test("The obsolete formal explorer refuses to omit action constraints")
    func legacyExplorerRejectsActionConstraint() throws {
        let compilation = try ActionConstrainedCounter.spec.compile()
        let checker = ModelChecker(compilation: compilation,
            configuration: try .init(maximumStateLimit: 4, symmetryReduction: .disabled))
        do {
            _ = try checker.explore()
            Issue.record("The formal explorer must not claim an unconstrained graph")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unsupportedActionConstraintEvaluation)
        }
    }
}

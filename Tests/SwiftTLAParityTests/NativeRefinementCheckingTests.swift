import Testing
@testable import SwiftTLA
import UpstreamParity

struct NativeRefinementCheckingTests {
    @Test("native refinement permits mapped stuttering independently of abstract exploration constraints")
    func acceptsNativeRefinement() throws {
        let graph = try ReachabilityGraph(initialMachines: NativeRefinementCounter.initialMachines(), maximumStates: 10)
        #expect(graph.transitions.count == 5)
        #expect(graph.refinementFailures.isEmpty)
        let exported = try NativeModelRun(graph, rendered: NativeRefinementCounter.render())
        #expect(exported.checks.properties["Refines"] == .satisfied)
        #expect(exported.rendered.refinementNames == ["Refines"])
        #expect(!exported.rendered.temporalNames.contains("Refines"))
        #expect(exported.rendered.tlaBundle.cfg.contains("PROPERTY Refines\n"))
        #expect(try exported.rendered.tlaBundle(checking: ["Refines"], checkDeadlock: false).cfg.contains("PROPERTY Refines\n"))
        guard case .violated(let trace) = exported.checks.deadlock else {
            Issue.record("Expected the terminal deadlock independently of the satisfied refinement")
            return
        }
        try trace.validate(in: exported.graph.graph)
    }

    @Test("incomplete native exploration cannot establish refinement")
    func incompleteNativeExplorationCannotEstablishRefinement() throws {
        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try ReachabilityGraph(initialMachines: NativeRefinementCounter.initialMachines(), maximumStates: 1)
        }
    }

    @Test("native refinement failures retain the actual initial state or violating edge")
    func reportsNativeRefinementFailures() throws {
        for initial in try InvalidNativeRefinement.initialMachines() {
            let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 4)
            let failure = try #require(graph.refinementFailures[.Refines])
            let exported = try NativeModelRun(graph, rendered: InvalidNativeRefinement.render())
            guard case .violated(let trace) = exported.checks.properties["Refines"],
                  case .violated = exported.checks.properties["BelowTwo"],
                  case .violated = exported.checks.properties["ReachesFour"] else {
                Issue.record("All refinement, invariant, and temporal failures must be retained")
                continue
            }
            if initial.state.count == 0 {
                guard case .transition(let source, let action, let target) = failure else {
                    Issue.record("Expected the concrete edge that skips an abstract state")
                    continue
                }
                #expect(source.state.count == 0 && target.state.count == 2)
                #expect(action == .advance)
                #expect(trace.steps.map(\.action) == [nil, "advance"])
            } else {
                #expect(failure == .initialState(initial.snapshot))
                #expect(trace.steps.count == 1)
            }
        }
    }

    @Test("native refinement reports unfair mapped stuttering")
    func reportsAbstractFairnessViolation() throws {
        let graph = try ReachabilityGraph(initialMachines: FairNativeRefinement.initialMachines(), maximumStates: 3)
        guard case .fairness(_, let witness) = try #require(graph.refinementFailures[.Refines]) else {
            Issue.record("Expected an abstract fairness counterexample")
            return
        }
        #expect(witness.cycle.first == witness.cycle.last)
        #expect(witness.cycleActions == [nil])
        let exported = try NativeModelRun(graph, rendered: FairNativeRefinement.render())
        guard case .violated(let trace) = exported.checks.properties["Refines"] else {
            Issue.record("Expected a retained refinement counterexample")
            return
        }
        #expect(trace.cycleStartIndex == witness.prefix.count - 1)
        #expect(trace.steps[try #require(trace.cycleStartIndex)].state == trace.steps.last?.state)
        #expect(trace.steps.last?.action == nil)
    }

    @Test("concrete fairness establishes abstract progress")
    func acceptsFairRefinement() throws {
        let graph = try ReachabilityGraph(initialMachines: FairConcreteRefinement.initialMachines(), maximumStates: 3)
        #expect(graph.refinementFailures.isEmpty)
    }

    @Test("abstract enabledness includes successors missing from the concrete graph")
    func checksUnreachableAbstractSuccessors() throws {
        let graph = try ReachabilityGraph(initialMachines: StoppedConcreteRefinement.initialMachines(), maximumStates: 2)
        guard case .fairness(_, let witness) = try #require(graph.refinementFailures[.Refines]) else {
            Issue.record("Expected missing abstract progress")
            return
        }
        #expect(witness.cycle.allSatisfy { $0.state.count == 1 })
    }

    @Test("refinement maps action enabledness from the generated machine")
    func mapsActionEnabledness() throws {
        let initial = try #require(EnablednessNativeRefinement.initialMachines().first)
        #expect(try Set(initial.enabledActions()) == [.ready, .advance])
        let advanced = try #require(initial.successors().first { $0.action == .advance })
        #expect(try advanced.machine.enabledActions().isEmpty)
        let graph = try ReachabilityGraph(initialMachines: EnablednessNativeRefinement.initialMachines(), maximumStates: 3)
        #expect(graph.transitions.count == 2)
        #expect(graph.refinementFailures.isEmpty)
        let exported = try NativeModelRun(graph, rendered: EnablednessNativeRefinement.render())
        #expect(exported.checks.properties["Refines"] == .satisfied)
    }
}

import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

struct NativeRefinementCheckingTests {
    @Test("native refinement permits mapped stuttering independently of abstract exploration constraints")
    func acceptsNativeRefinement() throws {
        let graph = try ReachabilityGraph(initialMachines: NativeRefinementCounter.initialMachines(), maximumStates: 10)
        #expect(graph.transitions.count == 5)
        #expect(graph.refinementFailures.isEmpty)
        let compilation = try NativeRefinementCounter.spec.compile()
        let exported = try NativeModelRun(graph, rendered: NativeRefinementCounter.render())
        #expect(exported.checks.properties["Refines"] == .satisfied)
        #expect(exported.rendered.refinementNames == ["Refines"])
        #expect(!exported.rendered.temporalNames.contains("Refines"))
        #expect(exported.rendered.tlaBundle.cfg.contains("PROPERTY Refines\n"))
        #expect(try exported.rendered.tlaBundle(checking: ["Refines"], checkDeadlock: false).cfg.contains("PROPERTY Refines\n"))
        let configuration = try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
        let formal = try ModelChecker(compilation: compilation, configuration: configuration).explore()
        #expect(formal.isComplete)
        #expect(formal.safetyViolations.map { $0.diagnostic?.kind } == [.deadlock])
        #expect(try RefinementChecker(compilation: compilation).check(formal) == nil)
        guard case .violated(let trace) = exported.checks.deadlock else {
            Issue.record("Expected the terminal deadlock independently of the satisfied refinement")
            return
        }
        try trace.validate(in: exported.graph.graph)
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

}

@TLAModel
private struct NativeRefinementCounter {
    static var spec: TLASpec {
        #spec("NativeRefinementCounter") { scope in
            let abstract = TLASpec("AbstractPairCounter") {
                let value = Var<Pair<Int, Int>>("value")
                Variable(value, Pair<Int, Int>.literal(0, 0))
                SwiftTLA.Action("advance") {
                    value.becomes(Pair<Int, Int>.literal(value.first() + 1, 0)).when(value.first() < 2)
                }
                Constraint(value.first() < 1)
            }
            let count = scope.sharedVar("count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 4) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance,
                mappings: [.init(Var<Pair<Int, Int>>("value"), from: Pair<Int, Int>.literal(count / 2, 0))])
            Refines
        }
    }
}

@TLAModel
private struct InvalidNativeRefinement {
    static var spec: TLASpec {
        #spec("InvalidNativeRefinement") { scope in
            let abstract = TLASpec("AbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
            }
            let count = scope.sharedVar("count", in: 0...1)
            Invariant("BelowTwo") { count < 2 }
            Eventually("ReachesFour", count == 4)
            SwiftTLA.Action("advance") { count.becomes(count + 2).when(count < 2) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
private struct FairNativeRefinement {
    static var spec: TLASpec {
        #spec("FairNativeRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar("count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
private struct FairConcreteRefinement {
    static var spec: TLASpec {
        #spec("FairConcreteRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar("count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
            WeakFairnessNext()
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
private struct StoppedConcreteRefinement {
    static var spec: TLASpec {
        #spec("StoppedConcreteRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar("count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 1) }
            WeakFairnessNext()
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

import Testing
import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

struct NativeRefinementCheckingTests {
    @Test("generated native refinement permits mapped stuttering and shared tuple types")
    func acceptsNativeRefinement() throws {
        let graph = try ReachabilityGraph(initialMachines: NativeRefinementCounter.initialMachines(), maximumStates: 10)
        #expect(graph.transitions.count == 5)
        #expect(graph.refinementFailures.isEmpty)
        #expect(try SwiftGraphExporter().export(graph).isPassEligible)
    }

    @Test("native refinement failures retain the actual initial state or violating edge")
    func reportsNativeRefinementFailures() throws {
        for initial in try InvalidNativeRefinement.initialMachines() {
            let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 4)
            let failure = try #require(graph.refinementFailures["Refines"])
            let exported = try SwiftGraphExporter().export(graph)
            #expect(exported.outcome == .refinementViolation("Refines"))
            let trace = try #require(exported.trace)
            if initial.state.count == 0 {
                guard case .transition(let source, let action, let target) = failure else {
                    Issue.record("Expected the concrete edge that skips an abstract state")
                    continue
                }
                #expect(source.state.count == 0 && target.state.count == 2)
                #expect(action == .advance)
                #expect(trace.steps.map(\.action) == ["Init", "advance"])
            } else {
                #expect(failure == .initialState(initial.snapshot))
                #expect(trace.steps.count == 1)
            }
        }
    }

    @Test("abstract fairness is rejected before native refinement exploration")
    func rejectsUncheckedAbstractFairness() throws {
        #expect(throws: ExplorationError.unsupportedRefinement("Refines")) {
            try ReachabilityGraph(initialMachines: FairNativeRefinement.initialMachines(), maximumStates: 1)
        }
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
            }
            let count = scope.sharedVar("count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 4) }
            let instance = Instance("Counter", of: abstract)
            instance
            Refinement(name: "Refines", instance: instance,
                mappings: [.init(Var<Pair<Int, Int>>("value"), from: Pair<Int, Int>.literal(count / 2, 0))])
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
            SwiftTLA.Action("advance") { count.becomes(count + 2).when(count < 2) }
            let instance = Instance("Counter", of: abstract)
            instance
            Refinement(name: "Refines", instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
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
            Refinement(name: "Refines", instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
        }
    }
}

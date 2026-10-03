import Testing
import SwiftTLA
import UpstreamParity

struct EWD840CorpusExecutionTests {
    @Test("each active EWD840 node can deactivate without changing the token or colors")
    func deactivationPreservesOtherState() throws {
        let initial = try EWD840Model.initialMachines()
        let actions: [(EWD840Model.Node, EWD840Model.Action)] = [
            (.zero, .Deactivate_0), (.one, .Deactivate_1), (.two, .Deactivate_2)
        ]
        for machine in initial {
            for (node, action) in actions {
                let active = try #require(machine.state.active[node] as Bool?)
                #expect(try machine.isEnabled(action) == active)
                guard active else { continue }
                var next = machine
                _ = try next.send(action)
                #expect(next.state.active[node] == false)
                for other in EWD840Model.Node.allCases where other != node {
                    #expect(next.state.active[other] == machine.state.active[other])
                }
                #expect(next.state.color == machine.state.color)
                #expect(next.state.tpos == machine.state.tpos)
                #expect(next.state.tcolor == machine.state.tcolor)
            }
        }
    }

    @Test("EWD840 native and formal execution preserve the complete three-node graph and deadlocks")
    func completeNativeGraphMatchesFormalGraph() throws {
        let initial = try EWD840Model.initialMachines()
        #expect(initial.count == 192)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 1_000)
        let compilation = try EWD840Model.spec.compile()
        let formal = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 1_000, symmetryReduction: .disabled)).explore()
        #expect(formal.isComplete)
        #expect(formal.graph.states.count == Example.ewd840.expectedDistinct)
        #expect(try CanonicalGraph(native) == FormalGraphExporter().export(formal).graph)
        let terminals = Set(native.transitions.keys.filter { native.transitions[$0]?.isEmpty == true })
        #expect(!terminals.isEmpty)
        #expect(Set(native.safetyViolations.keys) == terminals)
        #expect(native.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
        #expect(formal.safetyViolations.count == 1)
        #expect(formal.safetyViolations.first?.diagnostic?.kind == .deadlock)
    }
}

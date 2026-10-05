import Testing
import SwiftTLA
import UpstreamParity

struct EWD840CorpusExecutionTests {
    @Test("the published EWD840 scenario binds three nodes and disables deadlock checking")
    func publishedConfiguration() throws {
        let scenario = try #require(EWD840Model.validationScenarios().first)
        #expect(scenario.name == "EWD840")
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.cfg.contains("N = 3"))
        #expect(!rendered.checksDeadlock)
    }

    @Test("EWD840 preserves one System fairness obligation across native and TLA outputs")
    func systemActionFairness() throws {
        let configuration = try EWD840Model.Configuration(N: 3)
        let machine = try #require(EWD840Model.initialMachines(configuration: configuration).first)
        let conditions = try machine.fairnessConditions()
        #expect(conditions.count == 1)
        #expect(conditions[0].matches(.InitiateProbe))
        #expect(conditions[0].matches(.PassToken(i: 1)))
        #expect(!conditions[0].matches(.SendMsg(i: 1)))
        #expect(!conditions[0].matches(.Deactivate(i: 1)))
        let rendered = try EWD840Model.render(configuration: configuration)
        let obligations = rendered.tlaBundle.root.tla.split(separator: "\n").filter { $0.contains("WF_") }
        #expect(obligations.count == 1)
        #expect(obligations[0].contains("InitiateProbe"))
        #expect(obligations[0].contains("PassToken"))
        #expect(obligations[0].contains("\\/"))
    }

    @Test("each configured EWD840 node can deactivate without changing the token or colors")
    func deactivationPreservesOtherState() throws {
        let configuration = try EWD840Model.Configuration(N: 3)
        let initial = try EWD840Model.initialMachines(configuration: configuration)
        for machine in initial {
            for node in 0..<configuration.N {
                let action = EWD840Model.Action.Deactivate(i: node)
                let active = try #require(machine.state.active[node] as Bool?)
                #expect(try machine.isEnabled(action) == active)
                guard active else { continue }
                var next = machine
                _ = try next.send(action)
                #expect(next.state.active[node] == false)
                for other in 0..<configuration.N where other != node {
                    #expect(next.state.active[other] == machine.state.active[other])
                }
                #expect(next.state.color == machine.state.color)
                #expect(next.state.tpos == machine.state.tpos)
                #expect(next.state.tcolor == machine.state.tcolor)
            }
        }
    }

    @Test("EWD840 checks liveness and deadlocks on its complete three-node graph")
    func completeConfiguredNativeGraph() throws {
        let configuration = try EWD840Model.Configuration(N: 3)
        let initial = try EWD840Model.initialMachines(configuration: configuration)
        #expect(initial.count == 192)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 1_000)
        #expect(native.transitions.count == 302)
        #expect(native.temporalResults[.Liveness]?.status == .satisfied)
        #expect(try EWD840Model.render(configuration: configuration).checkNames.contains("Liveness"))
        let sender = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false && $0.state.active[2] == false
        })
        let outgoing = try #require(native.transitions[sender.snapshot])
        let sends = outgoing.filter { $0.action == .SendMsg(i: 0) }
        #expect(sends.count == 2)
        #expect(sends.contains { $0.target.state.active[1] == true && $0.target.state.active[2] == false })
        #expect(sends.contains { $0.target.state.active[1] == false && $0.target.state.active[2] == true })
        #expect(sends.allSatisfy { $0.target.state.color[0] == .black })
        let terminals = Set(native.transitions.keys.filter { native.transitions[$0]?.isEmpty == true })
        #expect(!terminals.isEmpty)
        #expect(Set(native.safetyViolations.keys) == terminals)
        #expect(native.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
    }

    @Test("EWD840's configured domain supplies all four-node initial functions")
    func fourNodeInitialFunctions() throws {
        let configuration = try EWD840Model.Configuration(N: 4)
        let initial = try EWD840Model.initialMachines(configuration: configuration)
        #expect(initial.count == 1_024)
        #expect(initial.allSatisfy {
            $0.state.active.count == 4 && $0.state.active.keys.contains(3)
                && $0.state.color.count == 4 && $0.state.color.keys.contains(3)
        })
    }
}

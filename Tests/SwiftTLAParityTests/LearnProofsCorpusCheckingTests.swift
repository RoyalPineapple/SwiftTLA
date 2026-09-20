import Testing
import SwiftTLA
import UpstreamParity

struct LearnProofsCorpusCheckingTests {
    @Test("AddTwo preserves the unbounded upstream transition without control state")
    func preservesAddTwo() throws {
        var machine = try AddTwoModel.makeMachine()
        #expect(machine.state.x == 0)
        for step in 1...100 {
            let successors = try machine.successors()
            #expect(successors.count == 1)
            let next = try #require(successors.first)
            #expect(next.action == .Next)
            #expect(next.machine.state.x == step * 2)
            _ = try machine.send(.Next)
            #expect(machine.state == next.machine.state)
        }
        let rendered = try AddTwoModel.render()
        #expect(!rendered.tlaBundle.cfg.contains("CONSTRAINT"))
        #expect(!rendered.tlaBundle.tla.contains("pc"))
        #expect(rendered.checkNames == ["TypeOK", "Even"])
    }

    @Test("MCFindHighest separates its substituted sequence domain from the state constraint")
    func preservesConfiguredDomain() throws {
        let scenario = try #require(FindHighestModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 781)
        #expect(initial.contains { $0.state.f.count == 4 })
        let graph = try scenario.explore(maximumStates: 10_000)
        #expect(graph.initialStates.count == 156)
        #expect(graph.transitions.count == 742)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.allSatisfy { $0.state.f.count <= 3 })
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "InductiveInvariant", "DoneIndexValue", "Correctness"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("CONSTRAINT"))
    }
}

import SwiftTLA
import Testing
import UpstreamParity

struct SimpleAllocatorCorpusFairnessTests {
    @Test("returning one of two held resources leaves the client's fair return outstanding")
    func returnAllHeldResources() throws {
        let scenario = try #require(SimpleAllocatorModel.validationScenarios().first)
        var machine = try #require(scenario.initialMachines().first)
        _ = try machine.send(.Request(client: .c1, requested: [.r1, .r2]))
        _ = try machine.send(.Allocate(client: .c1, granted: [.r1, .r2]))
        let before = machine.snapshot
        let obligations = try machine.fairnessConditions()
        let partial = SimpleAllocatorModel.Action.Return(client: .c1, returned: [.r1])
        let full = SimpleAllocatorModel.Action.Return(client: .c1, returned: [.r1, .r2])
        let returns = obligations.filter { !$0.isStrong && $0.matches(partial) }
        #expect(returns.count == 3)
        for (action, expected) in [(partial, 0), (full, 1)] {
            var after = machine
            _ = try after.send(action)
            var progressed = 0
            for obligation in returns {
                let changes = try #require(obligation.changes)
                if try changes(before, after.snapshot) { progressed += 1 }
            }
            #expect(progressed == expected)
        }
    }
}

import Testing
@testable import SwiftTLA

struct BoundChoiceDepletionTests {
    @Test("Every bound choice removes its selected member in one generated transition")
    func generatedChoicesDepleteTheSet() throws {
        let graph = try ReachabilityGraph(
            initialMachines: BoundChoiceDepletionModel.initialMachines(), maximumStates: 20
        )
        #expect(graph.transitions.count == 13)
        #expect(graph.transitions.values.flatMap { $0 }.count == 15)
        for (snapshot, transitions) in graph.transitions {
            let members = snapshot.state.source
            #expect(Set(transitions.map { $0.target.state.picked }) == members)
            for transition in transitions {
                #expect(transition.action == .pick)
                #expect(transition.target.state.source == members.subtracting([transition.target.state.picked]))
            }
        }
        let terminals = Set(graph.transitions.keys.filter { $0.state.source.isEmpty })
        #expect(terminals.count == 3)
        #expect(Set(graph.safetyViolations.keys) == terminals)
        #expect(graph.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
    }
}

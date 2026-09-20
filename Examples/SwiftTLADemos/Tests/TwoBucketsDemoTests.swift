import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct TwoBucketsDemoTests {
    @Test("two buckets exposes all generated puzzle moves")
    func exposesPuzzleMoves() throws {
        var machine = try TwoBuckets.makeMachine()

        #expect(try machine.isEnabled(.fillThree))
        #expect(try machine.isEnabled(.fillFive))
        #expect(try machine.isEnabled(.emptyThree) == false)

        _ = try machine.send(.fillThree)
        #expect(machine.state.three == 3)
        #expect(machine.state.five == 0)

        _ = try machine.send(.pourThreeIntoFive)
        #expect(machine.state.three == 0)
        #expect(machine.state.five == 3)
    }

    @Test("every reachable puzzle move preserves capacities and the poured amount")
    func preservesAllPuzzleMoves() throws {
        let graph = try ReachabilityGraph(initialMachines: TwoBuckets.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == 16)
        #expect(graph.safetyViolations.isEmpty)
        for (snapshot, transitions) in graph.transitions {
            let state = snapshot.state
            var expected: [TwoBuckets.Action: TwoBuckets.State] = [:]
            if state.three < 3 { expected[.fillThree] = .init(three: 3, five: state.five) }
            if state.five < 5 { expected[.fillFive] = .init(three: state.three, five: 5) }
            if state.three > 0 { expected[.emptyThree] = .init(three: 0, five: state.five) }
            if state.five > 0 { expected[.emptyFive] = .init(three: state.three, five: 0) }
            if state.three > 0 && state.five < 5 {
                let amount = min(state.three, 5 - state.five)
                expected[.pourThreeIntoFive] = .init(three: state.three - amount, five: state.five + amount)
            }
            if state.five > 0 && state.three < 3 {
                let amount = min(state.five, 3 - state.three)
                expected[.pourFiveIntoThree] = .init(three: state.three + amount, five: state.five - amount)
            }
            #expect(transitions.count == expected.count)
            for transition in transitions {
                #expect(expected[transition.action] == transition.target.state)
            }
        }
        #expect(try !TwoBuckets.render().tlaBundle.tla.contains("VARIABLES pc"))
    }
}

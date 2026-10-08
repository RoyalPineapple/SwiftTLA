import Testing
@testable import SwiftTLA

struct RandomSubsetExpressionTests {
    @Test("finite random subsets contain distinct source members and cap at the domain size")
    func finiteDomain() throws {
        #expect(try _NativeMachineOperations.randomSubset(upTo: 2, from: Set([1, 2, 3])).count == 2)
        #expect(try _NativeMachineOperations.randomSubset(upTo: 5, from: Set([1, 2])) == Set([1, 2]))
        #expect(try _NativeMachineOperations.randomSubset(upTo: 0, from: Set([1])) == [])
        #expect(throws: NativeMachineEvaluationError.invalidRandomSubsetCount(-1)) {
            try _NativeMachineOperations.randomSubset(upTo: -1, from: Set([1]))
        }
    }

    @Test("generated machines sample large function domains without enumerating the function space")
    func generatedFunctionDomain() throws {
        let machines = try RandomSubsetFunctionModel.initialMachines()
        #expect(machines.count == 100)
        let functions = Set(machines.map(\.state.samples))
        #expect(functions.count == 100)
        for function in functions {
            #expect(Set(function.keys) == Set(1...30))
        }
        let replay = try RandomSubsetFunctionModel.makeMachine(machines[0].state)
        #expect(replay.state.samples == machines[0].state.samples)
        let tla = try RandomSubsetFunctionModel.render().tlaBundle.tla
        #expect(tla.contains("EXTENDS Integers, Randomization"))
        #expect(tla.contains("RandomSubset(100, [1..30 -> {FALSE, TRUE}])"))
    }
}

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

    @Test("selected initialization accepts a valid function outside the latest random sample")
    func selectedFunctionOutsideSample() throws {
        let sampled = Set(try RandomSubsetFunctionModel.initialMachines().map(\.state.samples))
        let unsampled = (0...100).lazy.map { pattern in
            Dictionary(uniqueKeysWithValues: (1...30).map { key in
                (key, key <= 7 && pattern & (1 << (key - 1)) != 0)
            })
        }.first { !sampled.contains($0) }
        guard let unsampled else {
            Issue.record("101 distinct valid functions cannot all be in a 100-member sample")
            return
        }

        let selected = RandomSubsetFunctionModel.State(samples: unsampled)
        #expect(try RandomSubsetFunctionModel.makeMachine(selected).state == selected)
        var invalid = unsampled
        invalid[31] = false
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try RandomSubsetFunctionModel.makeMachine(.init(samples: invalid))
        }
    }

    @Test("formal evaluation samples a large function space without enumerating it")
    func interpretedFunctionDomain() throws {
        let sample = RandomSubset(upTo: 100,
            from: Functions(from: IntRange(1, through: 64), to: SetExpr<Bool>.literal(false, true)))
        guard case .set(let functions) = try evaluateClosed(sample.stateExpr) else {
            Issue.record("RandomSubset did not return a set")
            return
        }
        #expect(functions.count == 100)
        for value in functions {
            guard case .function(let mapping) = value else {
                Issue.record("RandomSubset returned a non-function member")
                continue
            }
            #expect(Set(mapping.keys) == Set((1...64).map(TLAValue.int)))
            #expect(mapping.values.allSatisfy { $0 == .bool(false) || $0 == .bool(true) })
        }
    }
}

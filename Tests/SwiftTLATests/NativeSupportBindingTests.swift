import Testing
import SwiftTLA

@Suite struct NativeSupportBindingTests {
    @Test("Generated initialization retains library behavior under caller overloads")
    func retainsLibraryInitialMeaningUnderCallerOverloads() throws {
        let initial = try NativeSupportBindingModel.initialOutcomes()
        #expect(initial.states.count == 1)
        #expect(initial.failures.isEmpty)
        #expect(try NativeSupportBindingModel.initialMachines().count == 1)
        var machine = try NativeSupportBindingModel.makeMachine()
        #expect(machine.state.seed == 0 && machine.state.count == 1)
        #expect(machine.state.minimum == Int.min)
        let count = try #require(TLAStateProjection.Token(validating: "count"))
        let projection = try machine.formalProjection(of: machine.snapshot)
        #expect(projection.value(for: count) == .int(1))
        #expect(try machine.send(.advance).after.count == 2)
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [2, Int.max])) {
            try machine.send(.overflow)
        }
        #expect(machine.snapshot == before)
    }
}

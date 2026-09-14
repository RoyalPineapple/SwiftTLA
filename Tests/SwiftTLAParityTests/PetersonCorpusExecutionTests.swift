import Testing
import SwiftTLA
import UpstreamParity

struct PetersonCorpusExecutionTests {
    @Test("the turn holder advances when both Peterson processes are waiting")
    func turnBreaksContention() throws {
        var machine = try PetersonModel.makeMachine()
        for process in PetersonModel.Process.allCases {
            _ = try machine.send(.a0(process: process))
            _ = try machine.send(.a1(process: process))
            _ = try machine.send(.a2(process: process))
        }
        #expect(machine.state.turn == .one)
        #expect(try machine.isEnabled(.a3(process: .one)))
        #expect(try !machine.isEnabled(.a3(process: .two)))
        _ = try machine.send(.a3(process: .one))
        #expect(try machine.isEnabled(.cs(process: .one)))
    }

    @Test("Peterson native exploration preserves the complete formal graph without deadlock")
    func nativeGraphMatchesFormalGraph() throws {
        let native = try ReachabilityGraph(initialMachines: PetersonModel.initialMachines(), maximumStates: 1_000)
        #expect(native.safetyViolations.isEmpty)
        let compilation = try PetersonModel.spec.compile()
        let formal = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 1_000, symmetryReduction: .disabled)).explore()
        #expect(formal.isComplete)
        #expect(try CanonicalGraph(native) == FormalGraphExporter().export(formal).graph)
    }
}

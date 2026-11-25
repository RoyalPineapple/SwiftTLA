import SwiftTLA
import Testing
import UpstreamParity

struct LockHSCorpusStutteringTests {
    @Test("both published refinements observe the complete target state, including the program counters")
    func publishedRefinements() throws {
        let scenario = try #require(try LockHSModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 100)
        #expect(graph.refinementFailures.isEmpty)
        let rendered = try scenario.render()
        #expect(rendered.refinementNames == ["Spec", "PSpec"])
        #expect(rendered.checkNames == ["LockInv", "TypeOKHS", "InvHS", "Spec", "PSpec"])
        #expect(Set(rendered.tlaBundle.imports.map(\.name)).isSuperset(of: ["Lock", "Peterson"]))
        let initial = try LockModel.makeMachine()
        let advanced = try LockModel._machineForRefinement(.init(lock: 1, pc: [1: "l1", 2: "l0"]), configuration: .init())
        #expect(advanced.state == initial.state)
        #expect(advanced.snapshot != initial.snapshot)
        #expect(try initial.successors().contains { $0.machine.snapshot == advanced.snapshot })
        #expect(throws: TLAStateProjectionDiagnostic.self) {
            try LockModel._machineForRefinement(.init(lock: 1, pc: [1: "a0", 2: "l0"]), configuration: .init())
        }
    }

    @Test("only the acquiring process can advance the two stutters, and only the first changes turn")
    func acquisitionHistory() throws {
        let initial = try LockHSModel.makeMachine()
        var machine = try #require(initial.successors(for: .NoStutter).first { $0.state.pc[1] == "l1" })
        _ = try machine.send(.l1HS(process: 1))
        let acquired = machine.state
        #expect(acquired.lock == 0 && acquired.pc[1] == "cs")
        #expect(acquired.s == .second(.init(id: "l1", ctxt: 1, val: 2)))
        #expect(acquired.h_turn == 1)
        #expect(try !machine.isEnabled(.NoStutter))
        #expect(try !machine.isEnabled(.l1HS(process: 2)))
        _ = try machine.send(.l1HS(process: 1))
        #expect(machine.state.h_turn == 2)
        #expect(machine.state.s == .second(.init(id: "l1", ctxt: 1, val: 1)))
        #expect(machine.state.pc == acquired.pc && machine.state.lock == acquired.lock)
        _ = try machine.send(.l1HS(process: 1))
        #expect(machine.state.s == .first(.init(top: "top")))
        #expect(machine.state.pc == acquired.pc && machine.state.lock == acquired.lock && machine.state.h_turn == 2)
        #expect(try machine.isEnabled(.NoStutter))
    }
}

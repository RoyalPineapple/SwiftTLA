import Testing
import SwiftTLA
import UpstreamParity

struct LoopInvarianceCorpusCheckingTests {
    @Test("MCBinarySearch preserves positive sorted inputs and every selected property")
    func preservesBinarySearchConfiguration() throws {
        let scenario = try #require(BinarySearchModel.validationScenarios().first)
        #expect(scenario.name == "MCBinarySearch")
        let initial = try scenario.initialMachines()
        #expect(initial.count == 6_430)
        #expect(initial.allSatisfy { machine in
            let state = machine.state
            return (1...8).contains(state.seq.count)
                && state.seq == state.seq.sorted()
                && state.seq.allSatisfy { (1...5).contains($0) }
                && (1...5).contains(state.val)
                && state.low == 1 && state.high == state.seq.count && state.result == 0
        })
        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == Set(["resultCorrect", "TypeOK", "Inv", "Termination"]))
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.tla.contains("WF_<<pc, seq, val, low, high, result>>(Next)"))
        #expect(rendered.tlaBundle.cfg.contains("PROPERTY Termination"))
    }
}

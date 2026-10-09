import Foundation
import Testing

@Suite("Conditional step proof input")
struct ConditionalStepProofTests {
    @Test("Both generated conditional branches choose their declared value")
    func generatedConditionalBranches() throws {
        let initial = try ConditionalStepProofModel.initialMachines()
        #expect(initial.count == 2)
        for machine in initial {
            let successors = try machine.successors(for: .choose)
            #expect(successors.count == 1)
            let successor = try #require(successors.first)
            #expect(successor.state.value == (machine.state.chooseFirst ? 1 : 2))
            #expect(successor.state.chooseFirst == machine.state.chooseFirst)
            #expect(try !successor.isEnabled(.choose))
        }
        let rendered = try ConditionalStepProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalStepProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))
    }
}

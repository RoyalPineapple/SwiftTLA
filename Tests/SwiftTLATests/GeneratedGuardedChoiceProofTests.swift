import Foundation
import Testing

@Suite("Generated guarded choice proof input")
struct GeneratedGuardedChoiceProofTests {
    @Test("The checked guarded-choice TLA module is actual output, with two native successors")
    func generatedMachineChoice() throws {
        let rendered = try GeneratedGuardedChoiceProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedGuardedChoiceProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))

        let machine = try GeneratedGuardedChoiceProofModel.makeMachine()
        #expect(try machine.formalCall(for: .choose).name == "choose")
        #expect(machine.state.selected == 0)
        let successors = try machine.successors(for: .choose)
        #expect(Set(successors.map(\.state.selected)) == [1, 2])
        for successor in successors {
            #expect(try !successor.isEnabled(.choose))
        }
    }
}

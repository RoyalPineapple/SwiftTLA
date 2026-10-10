import Foundation
import SwiftTLA
import Testing

@Suite("Dependent initialization output proof input")
struct DependentInitializationOutputProofTests {
    @Test("Generated initial machines and checked TLA module retain dependent choices")
    func emittedInitialStates() throws {
        let machines = try DependentInitializationOutputProofModel.initialMachines()
        #expect(Set(machines.map { [$0.state.seed, $0.state.choice] }) == [[0, 0], [1, 0], [1, 1]])

        let rendered = try DependentInitializationOutputProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/DependentInitializationOutputProofModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == checkedModule)
    }
}

import Foundation
@testable import SwiftTLA
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

        let predicates = [
            "pc = \"finish\"",
            "seed \\in 0..1",
            "choice \\in (IF (seed = 0) THEN {0} ELSE {0, 1})",
        ]
        let missingDependentClause = rendered.replacingOccurrences(
            of: "  /\\ choice \\in (IF (seed = 0) THEN {0} ELSE {0, 1})\n", with: "")
        #expect(missingDependentClause != rendered)
        do {
            try verifyRenderedInitialConjunction(missingDependentClause, predicates: predicates)
            Issue.record("A missing dependent initializer was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
            #expect(diagnostic.actual == "Init ==\n  /\\ pc = \"finish\"\n  /\\ seed \\in 0..1")
        }
    }
}

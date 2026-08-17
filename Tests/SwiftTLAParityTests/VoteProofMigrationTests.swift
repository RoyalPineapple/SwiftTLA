import Testing
@testable import UpstreamParity

struct VoteProofMigrationTests {
    @Test("VoteProof preserves typed local recursion and formal module composition")
    func parserBuilderFidelity() throws {
        VoteProofModel._checkParserTree()

        let bundle = VoteProofModel.spec.tlaBundle
        #expect(bundle.root.tla.contains("C == INSTANCE Consensus"))
        #expect(bundle.imports.map(\.name).contains("Consensus"))
        #expect(bundle.root.tla.contains("SafeAt(value0, value1) =="))
        #expect(bundle.root.tla.contains("LET SA["))
        #expect(bundle.root.tla.contains("IN SA[value0]"))
        #expect(bundle.root.tla.contains("ChosenIn(b, v) =="))
        #expect(bundle.root.tla.contains("Refines == C!Spec"))

        let plusCal = try #require(VoteProofModel.spec.renderAuthoredPlusCalModules().first)
        #expect(plusCal.contains("--algorithm Voting"))
        #expect(plusCal.contains("SafeAt(value0, value1) =="))
        #expect(plusCal.contains("Refines == C!Spec"))
    }
}

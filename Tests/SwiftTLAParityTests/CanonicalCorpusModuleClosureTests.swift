import Testing
@testable import UpstreamParity

struct CanonicalCorpusModuleClosureTests {
    @Test("VoteProof links its complete pinned nonstandard module closure")
    func voteProofClosure() {
        let inputs = CanonicalCorpusModuleClosure.inputs(for: "voteproof-upstream-port")

        #expect(inputs.map(\.name).sorted() == [
            "FiniteSetTheorems", "Folds", "Functions", "NaturalsInduction", "TLAPS", "WellFoundedInduction"
        ])
        #expect(inputs.allSatisfy { $0.source.commit.count == 40 })
        #expect(inputs.allSatisfy { $0.sha256.count == 64 })
        #expect(CanonicalCorpusModuleClosure.inputs(for: "kvsnap-upstream-port").isEmpty)
    }
}

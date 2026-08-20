import Testing
@testable import UpstreamParity

struct CanonicalCorpusEntryTests {
    @Test("each canonical corpus model owns its pinned external closure")
    func corpusEntriesOwnExternalInputs() throws {
        let voteProof = try #require(
            CanonicalCorpus.entries.first { $0.id == "voteproof-upstream-port" }
        )
        let inputs = voteProof.externalInputs

        #expect(inputs.map(\.name).sorted() == [
            "FiniteSetTheorems", "Folds", "Functions", "NaturalsInduction", "TLAPS", "WellFoundedInduction"
        ])
        #expect(inputs.allSatisfy { $0.source.commit.count == 40 })
        #expect(inputs.allSatisfy { $0.sha256.count == 64 })
        #expect(voteProof.swiftConfiguration.contains("INVARIANTS TypeOK VInv1 VInv2 VInv3 VInv4"))
        #expect(voteProof.plusCalConfiguration.contains("PROPERTIES Refines"))
        let kvsnap = try #require(
            CanonicalCorpus.entries.first { $0.id == "kvsnap-upstream-port" }
        )
        #expect(kvsnap.externalInputs.isEmpty)
        #expect(kvsnap.swiftConfiguration == kvsnap.plusCalConfiguration)
        #expect(CanonicalCorpus.entries.map(\.id) == [
            "boulanger-upstream-port", "kvsnap-upstream-port", "voteproof-upstream-port"
        ])
    }
}

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
        #expect(voteProof.swiftConfiguration.tlaText.contains("INVARIANTS TypeOK VInv1 VInv2 VInv3 VInv4"))
        #expect(voteProof.plusCalConfiguration.tlaText.contains("PROPERTIES Refines"))
        #expect(voteProof.swiftConfiguration.checks.allSatisfy {
            if case .externalOnly = $0.support { return true }
            return false
        })
        let kvsnap = try #require(
            CanonicalCorpus.entries.first { $0.id == "kvsnap-upstream-port" }
        )
        #expect(kvsnap.externalInputs.isEmpty)
        #expect(kvsnap.swiftConfiguration.tlaText == kvsnap.plusCalConfiguration.tlaText)
        #expect(CanonicalCorpus.entries.map(\.id) == [
            "boulanger-upstream-port", "kvsnap-upstream-port", "voteproof-upstream-port"
        ])
    }

    @Test("corpus configuration checks are compiled or explicitly external-only")
    func configurationChecksHaveOneDeclaredOwner() throws {
        for entry in CanonicalCorpus.entries {
            try entry.validateConfigurationReferences(in: entry.specification().compile())
        }

        let invalid = CanonicalCorpusEntry(
            id: "invalid",
            specification: { BoulangerModel.spec },
            swiftConfiguration: .init(checks: [.init("Missing", kind: .invariant)]),
            plusCalConfiguration: .init()
        )
        #expect(throws: CanonicalCorpusConfigurationError.unresolvedCheck(
            entryID: "invalid", name: "Missing", kind: .invariant
        )) {
            try invalid.validateConfigurationReferences(in: BoulangerModel.spec.compile())
        }
    }
}

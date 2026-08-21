import Testing
@testable import UpstreamParity

struct CanonicalCorpusEntryTests {
    @Test("each canonical corpus model owns its compiled module closure")
    func corpusEntriesOwnCompiledModuleClosure() throws {
        let voteProof = try #require(
            CanonicalCorpus.entries.first { $0.id == "voteproof-upstream-port" }
        )
        #expect(try voteProof.specification().compile().renderedTLAModuleBundle().imports.map(\.name) == ["Consensus"])
        #expect(voteProof.swiftConfiguration.tlaText.contains("INVARIANTS TypeOK VInv1 VInv2 VInv3 VInv4"))
        #expect(voteProof.plusCalConfiguration.tlaText.contains("PROPERTIES Refines"))
        try voteProof.validateConfigurationReferences(in: voteProof.specification().compile())
        let kvsnap = try #require(
            CanonicalCorpus.entries.first { $0.id == "kvsnap-upstream-port" }
        )
        #expect(kvsnap.swiftConfiguration.tlaText == kvsnap.plusCalConfiguration.tlaText)
        #expect(CanonicalCorpus.entries.map(\.id) == [
            "boulanger-upstream-port", "kvsnap-upstream-port", "voteproof-upstream-port"
        ])
    }

    @Test("corpus configuration checks are compiled declarations")
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

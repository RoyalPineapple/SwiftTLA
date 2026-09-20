import Testing
@testable import UpstreamParity

struct CanonicalCorpusEntryTests {
    @Test("each canonical corpus model owns its compiled module closure")
    func corpusEntriesOwnCompiledModuleClosure() throws {
        let voteProof = try #require(CanonicalCorpus.entries.first { $0.id == "voteproof-upstream-port" })
        let rendered = try voteProof.rendered()
        #expect(rendered.tlaBundle.imports.map(\.name) == ["VoteProof__Refinement0"])
        #expect(rendered.tlaBundle.root.tla.contains("C == INSTANCE VoteProof__Refinement0 WITH chosen <-"))
        try rendered.tlaBundle.validateDeclaredClosure()
        #expect(rendered.tlaBundle.cfg.contains("PROPERTY Refines\n"))
        #expect(CanonicalCorpus.entries.map(\.id) == [
            "boulanger-upstream-port", "kvsnap-upstream-port", "tlcmc-graph-1", "voteproof-upstream-port"
        ])
    }

    @Test("corpus exports retain every compiled check in both backends")
    func configurationIncludesAllDeclaredChecks() throws {
        let sources = [BoulangerModel.spec, KVsnapModel.spec, TLCMCModel.spec, VoteProofModel.spec]
        for entry in CanonicalCorpus.entries {
            let rendered = try entry.rendered()
            let source = try #require(sources.first { $0.name == rendered.tlaBundle.root.name })
            let compiled = try source.compile()
            let configuration = rendered.tlaBundle.cfg
            try rendered.tlaBundle.validateDeclaredClosure()
            try rendered.plusCalBundle().validateDeclaredClosure()
            let directives = Set(configuration.split(separator: "\n").map(String.init))
            for name in compiled.description.invariants {
                #expect(directives.contains("INVARIANT \(name)"))
            }
            for name in compiled.description.temporalProperties + compiled.description.refinements {
                #expect(directives.contains("PROPERTY \(name)"))
            }
            if let constraint = compiled.description.stateConstraint {
                #expect(directives.contains("CONSTRAINT \(constraint)"))
            }
            if !compiled.description.temporalProperties.isEmpty || !compiled.description.refinements.isEmpty {
                #expect(!directives.contains { $0.hasPrefix("SYMMETRY ") })
            }
            #expect(try rendered.plusCalBundle().cfg == configuration)
        }
    }
}

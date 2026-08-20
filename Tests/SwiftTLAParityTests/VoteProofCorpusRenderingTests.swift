import Testing
@testable import UpstreamParity

struct VoteProofCorpusRenderingTests {
    @Test("VoteProof preserves typed local recursion and formal module composition")
    func parserBuilderFidelity() throws {
        VoteProofModel._checkParserTree()
        #expect(try VoteProofModel.spec.compile().spec.name == "VoteProof")

        let bundle = try VoteProofModel.spec.compile().renderedTLAModuleBundle()
        #expect(VoteProofModel.spec.constants == [
            "Value": .set([.string("v1"), .string("v2")]),
            "Acceptor": .set([.string("a1"), .string("a2"), .string("a3")]),
            "Quorum": .set([
                .set([.string("a1"), .string("a2")]),
                .set([.string("a1"), .string("a3")]),
                .set([.string("a2"), .string("a3")]),
                .set([.string("a1"), .string("a2"), .string("a3")])
            ]),
            "Ballot": .set([.int(0), .int(1), .int(2)])
        ])
        #expect(bundle.root.tla.contains("ASSUME Value = {\"v1\", \"v2\"}"))
        #expect(bundle.root.tla.contains("ASSUME Acceptor = {\"a1\", \"a2\", \"a3\"}"))
        #expect(bundle.root.tla.contains("C == INSTANCE Consensus"))
        #expect(bundle.imports.map(\.name).contains("Consensus"))
        #expect(bundle.root.tla.contains("SafeAt(value0, value1) =="))
        #expect(bundle.root.tla.contains("LET SA["))
        #expect(bundle.root.tla.contains("IN SA[value0]"))
        #expect(bundle.root.tla.contains("THEN TRUE ELSE ((SA["))
        #expect(bundle.root.tla.contains(")) /\\ \\A x7 \\in (x4 + 1)..(x1 - 1)"))
        #expect(bundle.root.tla.contains("ChosenIn(b, v) =="))
        #expect(bundle.root.tla.contains("Refines == C!Spec"))

        let plusCal = try VoteProofModel.spec.compile().authoredPlusCalBundle().root.tla
        #expect(plusCal.contains("--algorithm Voting"))
        let algorithmRange = try #require(plusCal.range(of: "(*--algorithm Voting"))
        let defineRange = try #require(plusCal.range(of: "define {"))
        let defineEndRange = try #require(plusCal.range(of: "}\n\nfair process"))
        let refinesRange = try #require(plusCal.range(of: "Refines == C!Spec"))
        let instanceRange = try #require(plusCal.range(of: "C == INSTANCE Consensus"))
        let safeAtRange = try #require(plusCal.range(of: "SafeAt(value0, value1) =="))
        let chosenRange = try #require(plusCal.range(of: "ChosenIn(b, v) =="))
        #expect(defineRange.lowerBound > algorithmRange.lowerBound)
        #expect(defineRange.lowerBound < safeAtRange.lowerBound)
        #expect(chosenRange.lowerBound < instanceRange.lowerBound)
        #expect(instanceRange.lowerBound < refinesRange.lowerBound)
        #expect(refinesRange.lowerBound < defineEndRange.lowerBound)
    }
}

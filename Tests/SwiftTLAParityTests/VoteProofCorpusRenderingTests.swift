import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct VoteProofCorpusRenderingTests {
    @Test("VoteProof retains nested typed binder identities during execution")
    func nestedTypedBindersExecute() throws {
        let exploration = try ModelChecker(
            compilation: try VoteProofModel.spec.compile(),
            configuration: try .init(maximumStateLimit: 1, symmetryReduction: .disabled)
        ).explore()

        #expect(exploration.graph.states.count == 1)
    }

    @Test("VoteProof #spec macro compiles and preserves typed local recursion and formal module composition")
    func specMacroCompilationPreservesFormalStructure() throws {
        let source = VoteProofModel.spec
        let compilation = try source.compile()
        let lowered = try source.loweredSourceModel()
        #expect(compilation.description.name == "VoteProof")
        #expect(Set(compilation.description.variables.map(\.name)).isSuperset(of: Set(["votes", "maxBal"])))
        #expect(Set(lowered.formalOperatorDefinitions.map(\.name)) == [
            "ChosenIn", "SafeAt", "chosen", "VoteProofTypeOK",
            "VoteProofSingleVotePerBallot", "VoteProofVotesAreSafe",
            "VoteProofAgreement", "VoteProofChosenValuesAgree"
        ])
        #expect(Set(compilation.description.invariants) == ["TypeOK", "VInv1", "VInv2", "VInv3", "VInv4"])
        #expect(compilation.description.refinements == ["Refines"])
        let definitions = Dictionary(uniqueKeysWithValues: lowered.formalOperatorDefinitions.map {
            ($0.name, $0)
        })
        #expect(definitions["VoteProofVotesAreSafe"]?.plusCalDependencies == ["SafeAt"])
        #expect(definitions["VoteProofChosenValuesAgree"]?.plusCalDependencies == ["chosen"])

        let bundle = compilation.renderedTLAModuleBundle()
        #expect(source.constants == [
            ConstantDecl("Value", .set([.string("v1"), .string("v2")])),
            ConstantDecl("Acceptor", .set([.string("a1"), .string("a2"), .string("a3")])),
            ConstantDecl("Quorum", .set([
                .set([.string("a1"), .string("a2")]),
                .set([.string("a1"), .string("a3")]),
                .set([.string("a2"), .string("a3")]),
                .set([.string("a1"), .string("a2"), .string("a3")])
            ])),
            ConstantDecl("Ballot", .set([.int(0), .int(1), .int(2)]))
        ])
        #expect(bundle.root.tla.contains("ASSUME Value = {\"v1\", \"v2\"}"))
        #expect(bundle.root.tla.contains("ASSUME Acceptor = {\"a1\", \"a2\", \"a3\"}"))
        #expect(bundle.root.tla.contains("C == INSTANCE Consensus"))
        #expect(bundle.imports.map(\.name).contains("Consensus"))
        let consensus = try #require(bundle.imports.first(where: { $0.name == "Consensus" }))
        #expect(consensus.tla.contains("Init == chosen = {}"))
        #expect(bundle.root.tla.contains("SafeAt(value0, value1) =="))
        #expect(bundle.root.tla.contains("LET SA["))
        #expect(!bundle.root.tla.contains("LET RECURSIVE SA"))
        #expect(bundle.root.tla.contains("IN SA[value0]"))
        #expect(bundle.root.tla.contains("THEN TRUE ELSE (SA["))
        #expect(bundle.root.tla.contains(")) /\\ \\A "))
        #expect(bundle.root.tla.contains(" \\in ("))
        #expect(bundle.root.tla.contains("ChosenIn(value0, value1) =="))
        #expect(bundle.root.tla.contains("VoteProofTypeOK =="))
        #expect(bundle.root.tla.contains("TypeOK == VoteProofTypeOK"))
        #expect(bundle.root.tla.contains("VInv4 == VoteProofChosenValuesAgree"))
        #expect(bundle.root.tla.contains("Refines == C!Spec"))

        let plusCal = try compilation.renderedPlusCalBundle().root.tla
        #expect(plusCal.contains("--algorithm Voting"))
        #expect(!plusCal.contains("LET RECURSIVE SA"))
        let algorithmRange = try #require(plusCal.range(of: "(*--algorithm Voting"))
        let defineRange = try #require(plusCal.range(of: "define {"))
        let defineEndRange = try #require(plusCal.range(of: "}\n\nprocess"))
        let refinesRange = try #require(plusCal.range(of: "Refines == C!Spec"))
        let instanceRange = try #require(plusCal.range(of: "C == INSTANCE Consensus"))
        let safeAtRange = try #require(plusCal.range(of: "SafeAt(value0, value1) =="))
        let chosenRange = try #require(plusCal.range(of: "ChosenIn(value0, value1) =="))
        #expect(plusCal.components(separatedBy: "C == INSTANCE Consensus").count == 2)
        #expect(defineRange.lowerBound > algorithmRange.lowerBound)
        #expect(defineRange.lowerBound < safeAtRange.lowerBound)
        #expect(chosenRange.lowerBound < defineEndRange.lowerBound)
        #expect(chosenRange.lowerBound < instanceRange.lowerBound)
        #expect(instanceRange.lowerBound < refinesRange.lowerBound)
    }
}

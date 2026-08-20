import Testing
@testable import SwiftTLA

@Suite("byzpaxos Consensus formal module")
struct ByzPaxosConsensusModuleTests {
  @Test("default instance resolves VoteProof's Value and chosen substitutions")
  func defaultInstanceRetainsRefinementParameters() throws {
    let consumer = TLASpec("VoteProofConsumer") {
      Parameter("Value")
      Definition("chosen == {}")
      Definition("Mention == \"C!Spec\"")
      Instance("C", of: ByzPaxosConsensus.module)
      Definition("Refines == C!Spec", named: "Refines", dependsOn: ["C"])
    }

    #expect(FormalModuleRegistry.lookup("Consensus") == ByzPaxosConsensus.module)
    #expect(FormalModuleRegistry.lookup("ByzPaxosConsensus") == ByzPaxosConsensus.module)
    let consumerModule = try consumer.compile().renderedTLAModuleBundle().tla
    #expect(consumerModule.contains("C == INSTANCE Consensus"))
    let chosenRange = try #require(consumerModule.range(of: "chosen == {}"))
    let mentionRange = try #require(consumerModule.range(of: "Mention == \"C!Spec\""))
    let instanceRange = try #require(consumerModule.range(of: "C == INSTANCE Consensus"))
    let refinesRange = try #require(consumerModule.range(of: "Refines == C!Spec"))
    #expect(chosenRange.lowerBound < instanceRange.lowerBound)
    #expect(mentionRange.lowerBound < instanceRange.lowerBound)
    #expect(instanceRange.lowerBound < refinesRange.lowerBound)
    #expect(try consumer.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Consensus"])
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("CONSTANTS Value"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("VARIABLES chosen"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("vars == <<chosen>>"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("LiveSpecEquals == LiveSpec"))
  }

  @Test("direct module dependencies must name a local declaration")
  func rejectsUnknownDirectModuleDependency() {
    let consumer = TLASpec("UnknownDependency") {
      Definition("Refines == Missing!Spec", named: "Refines", dependsOn: ["Missing"])
    }

    #expect(throws: CompilationDiagnostic.self) {
      try consumer.compile()
    }
  }

  @Test("direct module dependencies can name executable formal operators")
  func acceptsFormalOperatorDependency() throws {
    let consumer = TLASpec("FormalDependency") {
      FormalDefinition("SafeAt", taking: Int.self) { _ in true }
      Definition("TypeOK == SafeAt(1)", named: "TypeOK", dependsOn: ["SafeAt"])
    }

    _ = try consumer.compile()
  }
}

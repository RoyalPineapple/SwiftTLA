import Testing
@testable import SwiftTLA

@Suite("byzpaxos Consensus formal module")
struct ByzPaxosConsensusModuleTests {
  @Test("default instance resolves VoteProof's Value and chosen substitutions")
  func defaultInstanceRetainsRefinementParameters() throws {
    let consumer = TLASpec("VoteProofConsumer") {
      Parameter("Value")
      Definition("chosen == {}")
      Instance("C", of: ByzPaxosConsensus.module)
      Definition("Refines == C!Spec")
    }

    #expect(FormalModuleRegistry.lookup("Consensus") == ByzPaxosConsensus.module)
    #expect(FormalModuleRegistry.lookup("ByzPaxosConsensus") == ByzPaxosConsensus.module)
    let consumerModule = try consumer.compile().renderedTLAModuleBundle().tla
    #expect(consumerModule.contains("C == INSTANCE Consensus"))
    let chosenRange = try #require(consumerModule.range(of: "chosen == {}"))
    let instanceRange = try #require(consumerModule.range(of: "C == INSTANCE Consensus"))
    let refinesRange = try #require(consumerModule.range(of: "Refines == C!Spec"))
    #expect(chosenRange.lowerBound < instanceRange.lowerBound)
    #expect(instanceRange.lowerBound < refinesRange.lowerBound)
    #expect(try consumer.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Consensus"])
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("CONSTANTS Value"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("VARIABLES chosen"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("vars == <<chosen>>"))
    #expect(try ByzPaxosConsensus.module.compile().renderedTLAModuleBundle().tla.contains("LiveSpecEquals == LiveSpec"))
  }
}

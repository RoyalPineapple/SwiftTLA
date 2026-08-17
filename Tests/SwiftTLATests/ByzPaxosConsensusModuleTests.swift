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
    let consumerModule = consumer.tlaModule
    #expect(consumerModule.contains("C == INSTANCE Consensus"))
    let chosenRange = try #require(consumerModule.range(of: "chosen == {}"))
    let instanceRange = try #require(consumerModule.range(of: "C == INSTANCE Consensus"))
    let refinesRange = try #require(consumerModule.range(of: "Refines == C!Spec"))
    #expect(chosenRange.lowerBound < instanceRange.lowerBound)
    #expect(instanceRange.lowerBound < refinesRange.lowerBound)
    #expect(consumer.tlaBundle.imports.map(\.name) == ["Consensus"])
    #expect(ByzPaxosConsensus.module.tlaModule.contains("CONSTANTS Value"))
    #expect(ByzPaxosConsensus.module.tlaModule.contains("VARIABLES chosen"))
    #expect(ByzPaxosConsensus.module.tlaModule.contains("vars == <<chosen>>"))
    #expect(ByzPaxosConsensus.module.tlaModule.contains("LiveSpecEquals == LiveSpec"))
  }
}

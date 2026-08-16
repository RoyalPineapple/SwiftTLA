import Testing
@testable import SwiftTLA

@Suite("byzpaxos Consensus formal module")
struct ByzPaxosConsensusModuleTests {
  @Test("default instance retains VoteProof's Value and chosen substitutions")
  func defaultInstanceRetainsRefinementParameters() {
    let consumer = TLASpec("VoteProofConsumer") {
      Parameter("Value")
      Instance("C", of: ByzPaxosConsensus.module)
    }

    #expect(FormalModuleRegistry.lookup("Consensus") == ByzPaxosConsensus.module)
    #expect(consumer.tlaModule.contains("C == INSTANCE Consensus"))
    #expect(consumer.tlaBundle.imports.map(\.name) == ["Consensus"])
    #expect(ByzPaxosConsensus.module.tlaModule.contains("CONSTANTS Value"))
    #expect(ByzPaxosConsensus.module.tlaModule.contains("VARIABLES chosen"))
    #expect(ByzPaxosConsensus.module.tlaModule.contains("LiveSpecEquals == LiveSpec"))
  }
}

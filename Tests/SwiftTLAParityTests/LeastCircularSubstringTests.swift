import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Least Circular Substring module port")
struct LeastCircularSubstringTests {
  @Test("emits the upstream dependency as a separate module with its scoped finite configuration")
  func emitsModuleBundle() throws {
    let bundle = try LeastCircularSubstringModel.spec.tlaBundle
    guard let config = bundle.root.cfg else {
      Issue.record("The root module needs a TLC configuration.")
      return
    }

    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(bundle.root.tla.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    #expect(bundle.root.tla.contains("ZSequencesNat == 0..6"))
    #expect(config.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    #expect(config.contains("INVARIANT TypeInvariant"))
    #expect(config.contains("INVARIANT Correctness"))
  }

  @Test("preserves the published small-model state-space declaration")
  func retainsPublishedStateCount() {
    #expect(Example.leastCircularSubstring.expectedDistinct == 8_554)
    #expect(LeastCircularSubstringModel.spec.actions.map(\.name) == [
      "L3", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12", "L13", "L14", "LVR", "Terminating"
    ])
  }
}

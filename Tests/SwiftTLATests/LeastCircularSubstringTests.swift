import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Least Circular Substring module port")
struct LeastCircularSubstringTests {
  @Test("emits the upstream dependency as a separate module with its scoped finite configuration")
  func emitsModuleBundle() {
    let bundle = LeastCircularSubstringModel.spec.tlaBundle

    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(bundle.root.tla.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    #expect(bundle.root.tla.contains("ZSequencesNat == 0..6"))
    #expect(bundle.root.cfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    #expect(bundle.root.cfg.contains("INVARIANT TypeInvariant"))
    #expect(bundle.root.cfg.contains("INVARIANT Correctness"))
  }

  @Test("preserves the published small-model state-space declaration")
  func retainsPublishedStateCount() {
    #expect(Example.leastCircularSubstring.expectedDistinct == 8_554)
    #expect(LeastCircularSubstringModel.spec.actions.map(\.name) == [
      "L3", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12", "L13", "L14", "LVR", "Terminating"
    ])
  }
}

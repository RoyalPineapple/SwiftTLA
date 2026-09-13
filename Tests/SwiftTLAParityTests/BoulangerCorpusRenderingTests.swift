import Foundation
import Testing
@testable import UpstreamParity

struct BoulangerCorpusRenderingTests {
    @Test("The pinned Boulanger graph fixture matches generated TLA")
    func pinnedNativeValidationModule() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Verification/FiniteGraph/fixtures/boulanger/Boulanger.tla")
        let generated = try BoulangerModel.spec.compile().render().tlaBundle.root.tla
        #expect(try String(contentsOf: fixture, encoding: .utf8) == generated)
    }

    @Test("Boulanger preserves its Algorithm source through parser and builder")
    func parserBuilderFidelity() throws {

        let module = try BoulangerModel.spec.compile().render().plusCalBundle().root.tla
        #expect(module.contains("fair process"))
        #expect(module.contains("StateConstraint =="))
        #expect(module.contains("MutualExclusion =="))
        #expect(module.contains("w2"))
    }
}

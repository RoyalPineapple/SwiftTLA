import Testing
@testable import UpstreamParity

struct BoulangerCorpusRenderingTests {
    @Test("Boulanger preserves its Algorithm source through parser and builder")
    func parserBuilderFidelity() throws {
        BoulangerModel._checkParserTree()

        let module = try BoulangerModel.spec.compile().authoredPlusCalBundle().root.tla
        #expect(module.contains("fair process"))
        #expect(module.contains("StateConstraint =="))
        #expect(module.contains("MutualExclusion =="))
        #expect(module.contains("w2"))
    }
}

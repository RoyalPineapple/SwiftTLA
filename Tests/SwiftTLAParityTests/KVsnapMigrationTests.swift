import Testing
@testable import UpstreamParity

struct KVsnapMigrationTests {
    @Test("KVsnap preserves its typed Algorithm model through parser and builder")
    func parserBuilderFidelity() {
        KVsnapModel._checkParserTree()

        let bundle = KVsnapModel.spec.tlaBundle
        #expect(bundle.root.tla.contains("CC == INSTANCE ClientCentric"))
        #expect(bundle.imports.map(\.name).contains("ClientCentric"))
        #expect(bundle.root.tla.contains("CONSTANTS NoVal, k1, k2, t1, t2, t3"))
        #expect(bundle.cfg.contains("CONSTANT k1 = k1"))
    }
}

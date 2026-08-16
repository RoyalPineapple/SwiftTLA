import Testing
@testable import UpstreamParity

struct KVsnapMigrationTests {
    @Test("KVsnap preserves its typed Algorithm model through parser and builder")
    func parserBuilderFidelity() {
        KVsnapModel._checkParserTree()

        let bundle = KVsnapModel.spec.tlaBundle
        #expect(bundle.root.tla.contains("CC == INSTANCE ClientCentric"))
        #expect(bundle.imports.map(\.name).contains("ClientCentric"))
    }
}

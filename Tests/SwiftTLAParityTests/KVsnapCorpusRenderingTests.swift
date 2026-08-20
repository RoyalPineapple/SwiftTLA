import Testing
@testable import UpstreamParity

struct KVsnapCorpusRenderingTests {
    @Test("KVsnap preserves its typed Algorithm model through parser and builder")
    func parserBuilderFidelity() throws {
        KVsnapModel._checkParserTree()

        let bundle = try KVsnapModel.spec.compile().renderedTLAModuleBundle()
        #expect(bundle.root.tla.contains("CC == INSTANCE ClientCentric"))
        #expect(bundle.imports.map(\.name).contains("ClientCentric"))
        #expect(bundle.root.tla.contains("CONSTANTS NoVal, k1, k2, t1, t2, t3"))
        #expect(bundle.cfg.contains("CONSTANT k1 = k1"))
        #expect(bundle.cfg.contains("SYMMETRY SymmTxId"))

        let plusCal = try #require(KVsnapModel.spec.compile().renderedAuthoredPlusCalModules().first)
        #expect(plusCal.contains("EXTENDS"))
        #expect(plusCal.contains("KeyValueStoreUtil"))
        #expect(plusCal.contains("CC == INSTANCE ClientCentric"))
        #expect(plusCal.contains("InitialState =="))
        #expect(plusCal.contains("SnapshotIsolation == CC!SnapshotIsolation(InitialState, Range(ops))"))
        #expect(!plusCal.contains("Termination =="))
        #expect(!plusCal.contains("__pcal_local_family:"))
        let initialState = try #require(plusCal.range(of: "InitialState =="))
        let instance = try #require(plusCal.range(of: "CC == INSTANCE ClientCentric"))
        let algorithm = try #require(plusCal.range(of: "(*--algorithm KVsnap {"))
        #expect(initialState.lowerBound < algorithm.lowerBound)
        #expect(instance.lowerBound < algorithm.lowerBound)
    }
}

import Testing
@testable import UpstreamParity

struct KVsnapCorpusRenderingTests {
    @Test("KVsnap compiled bundles preserve module closure and properties")
    func compiledBundlesPreserveModuleClosureAndProperties() throws {

        let bundle = try KVsnapModel.spec.compile().renderedTLAModuleBundle()
        #expect(bundle.root.tla.contains("CC == INSTANCE ClientCentric"))
        #expect(bundle.imports.map(\.name).contains("ClientCentric"))
        #expect(bundle.root.tla.contains("CONSTANTS NoVal, k1, k2, t1, t2, t3"))
        #expect(bundle.cfg.contains("CONSTANT k1 = k1"))
        #expect(bundle.cfg.contains("SYMMETRY SymmTxId"))

        let plusCalBundle = try KVsnapModel.spec.compile().renderedPlusCalBundle()
        let plusCal = plusCalBundle.root.tla
        #expect(plusCal.contains("EXTENDS"))
        #expect(plusCalBundle.imports.map(\.name).contains("Util"))
        #expect(plusCal.contains("CC == INSTANCE ClientCentric"))
        #expect(plusCal.contains("InitialState =="))
        #expect(plusCal.contains("SnapshotIsolation == \\A "))
        #expect(plusCal.contains("CC!SnapshotIsolation(InitialState, Range(ops))"))
        #expect(plusCal.contains("Termination ==") == false)
        let initialState = try #require(plusCal.range(of: "InitialState =="))
        let instance = try #require(plusCal.range(of: "CC == INSTANCE ClientCentric"))
        let algorithm = try #require(plusCal.range(of: "(*--algorithm KVsnap {"))
        #expect(initialState.lowerBound < algorithm.lowerBound)
        #expect(instance.lowerBound < algorithm.lowerBound)
    }
}

import Testing
@testable import UpstreamParity

struct KVsnapCorpusRenderingTests {
    @Test("KVsnap compiled bundles preserve module closure and properties")
    func compiledBundlesPreserveModuleClosureAndProperties() throws {

        let rendered = try KVsnapModel.spec.compile().render()
        let bundle = rendered.tlaBundle
        #expect(bundle.root.tla.contains("CC == INSTANCE ClientCentric"))
        #expect(bundle.imports.map(\.name).contains("ClientCentric"))
        #expect(bundle.root.tla.contains("CONSTANTS NoVal, k1, k2, t1, t2, t3"))
        #expect(bundle.cfg.contains("CONSTANT k1 = k1"))
        let plusCalBundle = try rendered.plusCalBundle()
        for configuration in [bundle.cfg, plusCalBundle.cfg] {
            #expect(configuration.contains("PROPERTY Termination"))
            #expect(configuration.contains("CHECK_DEADLOCK TRUE"))
            #expect(!configuration.contains("SYMMETRY"))
        }
        let plusCal = plusCalBundle.root.tla
        #expect(plusCal.contains("EXTENDS"))
        #expect(plusCalBundle.imports.map(\.name).contains("Util"))
        #expect(plusCal.contains("CC == INSTANCE ClientCentric"))
        #expect(plusCal.contains("InitialState =="))
        #expect(plusCal.contains("SnapshotIsolation == (\\A "))
        #expect(plusCal.contains("CC!SnapshotIsolation(InitialState, Range(ops))"))
        #expect(plusCal.contains("Termination ==") == false)
        let initialState = try #require(plusCal.range(of: "InitialState =="))
        let instance = try #require(plusCal.range(of: "CC == INSTANCE ClientCentric"))
        let algorithm = try #require(plusCal.range(of: "(*--algorithm KVsnap {"))
        #expect(initialState.lowerBound < algorithm.lowerBound)
        #expect(instance.lowerBound < algorithm.lowerBound)
    }

    @Test("KVsnap generated exports retain resolved operations and all selected checks")
    func generatedExportsRetainResolvedOperations() throws {
        let rendered = try KVsnapModel.render()
        for bundle in [rendered.tlaBundle, try rendered.plusCalBundle()] {
            try bundle.validateDeclaredClosure()
            #expect(Set(bundle.imports.map(\.name)) == ["Folds", "Functions", "Util"])
            #expect(bundle.root.tla.contains("SnapshotIsolation == (\\A "))
            #expect(bundle.root.tla.contains("__KVsnap_resolvedFunction"))
            #expect(bundle.cfg.contains("INVARIANT SnapshotIsolation\n"))
            #expect(bundle.cfg.contains("INVARIANT TypeOK\n"))
            #expect(bundle.cfg.contains("PROPERTY Termination\n"))
            #expect(bundle.cfg.contains("CHECK_DEADLOCK TRUE\n"))
            #expect(!bundle.cfg.contains("SYMMETRY"))
        }
    }
}

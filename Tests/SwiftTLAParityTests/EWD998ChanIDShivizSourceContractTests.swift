import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct EWD998ChanIDShivizSourceContractTests {
    @Test("the published ShiViz configuration and complete import closure stay pinned")
    func pinnedReferenceInputs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = root.appendingPathComponent("Verification/FiniteGraph/fixtures")
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self, from: Data(contentsOf:
            root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let base = try #require(manifest.cases.first { $0.id == "ewd998-chan-id-0" })
        let module = fixtures.appendingPathComponent("ewd998/EWD998ChanID_shiviz.tla")
        let cfg = fixtures.appendingPathComponent("ewd998/EWD998ChanID_shiviz.cfg")
        #expect(SHA256.hex(try Data(contentsOf: module)) ==
            "43739b7a7c0754fbb2cf5a7606df9bd9610fc4bc3f22b79aab559e2f4e630c98")
        #expect(SHA256.hex(try Data(contentsOf: cfg)) ==
            "4dab15b9fea40413c96361139310ee2502b305c9b69980f5ba3c39aa5c30719f")
        let dependencies = [TLAModuleBundle.ModuleDependency(
            importingModule: "EWD998ChanID_shiviz", importedModule: "EWD998ChanID",
            structuralPath: ["shiviz", "base"])] + base.dependencies.enumerated().map { index, edge in
                TLAModuleBundle.ModuleDependency(
                    importingModule: edge.importingModule, importedModule: edge.importedModule,
                    structuralPath: ["shiviz", String(index)])
            }
        let bundle = try TLCProcessRequest.declaredBundle(
            root: module, configuration: cfg,
            imports: ([base.module] + base.imports).map { fixtures.appendingPathComponent($0) },
            dependencies: dependencies)
        try bundle.validateDeclaredClosure()
        #expect(bundle.files.count == 10)
    }
}

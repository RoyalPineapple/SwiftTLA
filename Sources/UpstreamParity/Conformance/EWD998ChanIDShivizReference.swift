import Foundation
import SwiftTLA

/// Records the unmodified published configuration's TLC outcome before porting it.
package enum EWD998ChanIDShivizReference {
    package static func capture(
        repositoryRoot: URL, base: FiniteGraphManifest.Case,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin,
        timeout: TimeInterval, to output: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws {
        let id = "ewd998-chan-id-shiviz"
        guard base.id == "ewd998-chan-id-0", base.moduleSHA256 ==
            "c498e5e35a83d84257016fdf4ba359ddb40dbb5f3b2234656e32b419a5499e93"
        else { throw FiniteGraphCaseError.pinMismatch("EWD998ChanID base case") }
        let fixtures = repositoryRoot.appendingPathComponent("Verification/FiniteGraph/fixtures")
            .resolvingSymlinksInPath().standardizedFileURL
        let module = fixtures.appendingPathComponent("ewd998/EWD998ChanID_shiviz.tla")
        let cfg = fixtures.appendingPathComponent("ewd998/EWD998ChanID_shiviz.cfg")
        let moduleSHA = "43739b7a7c0754fbb2cf5a7606df9bd9610fc4bc3f22b79aab559e2f4e630c98"
        let cfgSHA = "4dab15b9fea40413c96361139310ee2502b305c9b69980f5ba3c39aa5c30719f"
        let baseModule = try RetainedFiles.resolve(fixtures.appendingPathComponent(base.module),
            beneath: fixtures)
        let imports = try ([base.module] + base.imports).map { path in
            try RetainedFiles.resolve(fixtures.appendingPathComponent(path), beneath: fixtures)
        }
        guard SHA256.hex(try Data(contentsOf: module)) == moduleSHA,
              SHA256.hex(try Data(contentsOf: cfg)) == cfgSHA,
              SHA256.hex(try Data(contentsOf: baseModule)) == base.moduleSHA256 else {
            throw FiniteGraphCaseError.pinMismatch(id)
        }
        let dependencies = [TLAModuleBundle.ModuleDependency(
            importingModule: "EWD998ChanID_shiviz", importedModule: "EWD998ChanID",
            structuralPath: [id, "dependencies", "0"])] +
            base.dependencies.enumerated().map { index, edge in
                TLAModuleBundle.ModuleDependency(
                    importingModule: edge.importingModule, importedModule: edge.importedModule,
                    structuralPath: [id, "dependencies", String(index + 1)])
            }
        let bundle = try TLCProcessRequest.declaredBundle(
            root: module, configuration: cfg, imports: imports,
            dependencies: dependencies)
        try bundle.validateDeclaredClosure()
        try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
        try GeneratedTLCOracle.retainGeneratedInputs(bundle,
            in: output.appendingPathComponent("reference-input"))
        let work = output.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let check = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: Int.max, symmetryReduction: .disabled),
            moduleSHA256: moduleSHA, cfgSHA256: cfgSHA,
            arguments: ["-workers", "1", "-fp", "1", "-noTE", "-deadlock",
                "-generate", "-depth", "99999"], environment: [:], pin: pin)
        let request = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            bundle: bundle, graphEvents: work.appendingPathComponent("unused.bin"),
            traceOutput: work.appendingPathComponent("counterexample.json"),
            workingDirectory: work, finiteGraphCase: check, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let outcome = try process.run(request, retainingIn: output.appendingPathComponent("tlc"))
        try RetainedFiles.writeJSON([
            "schema": "swifttla.ewd998-shiviz-reference",
            "caseID": id, "result": "terminal", "tlcOutcome": String(describing: outcome),
            "modelCheckComplete": outcome == .completed,
            "moduleSHA256": moduleSHA, "cfgSHA256": cfgSHA,
            "baseModuleSHA256": base.moduleSHA256
        ], to: output.appendingPathComponent("report.json"))
    }
}

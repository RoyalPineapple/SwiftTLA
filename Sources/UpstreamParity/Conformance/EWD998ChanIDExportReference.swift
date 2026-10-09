import Foundation
import SwiftTLA

/// Probes the published configuration while intercepting its external HTTP POST.
package enum EWD998ChanIDExportReference {
    private static let caseID = "ewd998-chan-id-export"
    private static let moduleSHA = "638f814c422250d6debe1209419971b66ead59c8aa8aca4a2efcc29feb379985"
    private static let cfgSHA = "a02a94fce512a1c7f8c47f0c35bbad7813dfedbafec7212d2404c585541b078a"
    private static let communityNames: Set<String> = [
        "FiniteSetsExt", "Folds", "Functions", "IOUtils", "SequencesExt", "VectorClocks"
    ]
    private static let curlScript = """
        #!/bin/sh
        if [ "$#" -ne 7 ] || [ "$1" != "-H" ] || [ "$2" != "Content-Type:application/json" ] || \
           [ "$3" != "-X" ] || [ "$4" != "POST" ] || [ "$5" != "-d" ] || \
           [ "$7" != "https://postman-echo.com/post" ] || \
           [ -z "$SWIFTTLA_BLOCKED_POST_PAYLOAD" ] || [ -e "$SWIFTTLA_BLOCKED_POST_PAYLOAD" ]; then
          exit 64
        fi
        printf '%s' "$6" > "$SWIFTTLA_BLOCKED_POST_PAYLOAD"
        printf '%s' '{"networkBlocked":true}'
        """

    private struct CommunityLock: Decodable {
        let schema: String
        let tag: String
        let commit: String
        let jar: Jar
        let modules: [String: String]

        struct Jar: Decodable {
            let url: String
            let sha256: String
        }
    }

    package static func stageCurlInterceptor(in output: URL) throws -> (executable: URL, payload: URL) {
        let directory = output.appendingPathComponent("interception")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let executable = directory.appendingPathComponent("curl")
        try Data(curlScript.utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (executable, output.appendingPathComponent("blocked-post-payload.json"))
    }

    package static func capture(
        repositoryRoot: URL, base: FiniteGraphManifest.Case, toolRoot: URL,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin,
        timeout: TimeInterval, to output: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws {
        guard base.id == "ewd998-chan-id-0", base.moduleSHA256 ==
            "c498e5e35a83d84257016fdf4ba359ddb40dbb5f3b2234656e32b419a5499e93"
        else { throw FiniteGraphCaseError.pinMismatch("EWD998ChanID base case") }
        let fixtures = repositoryRoot.appendingPathComponent("Verification/FiniteGraph/fixtures")
            .resolvingSymlinksInPath().standardizedFileURL
        let module = fixtures.appendingPathComponent("ewd998/EWD998ChanID_export.tla")
        let cfg = fixtures.appendingPathComponent("ewd998/EWD998ChanID_export.cfg")
        guard SHA256.hex(try Data(contentsOf: module)) == moduleSHA,
              SHA256.hex(try Data(contentsOf: cfg)) == cfgSHA else {
            throw FiniteGraphCaseError.pinMismatch(caseID)
        }
        let lock = try JSONDecoder().decode(CommunityLock.self, from: Data(contentsOf:
            repositoryRoot.appendingPathComponent("Verification/FiniteGraph/community-modules.json")))
        guard lock.schema == "PinnedCommunityModules", lock.tag == "202609120237",
              lock.commit == "9aae8ea1318b3ded4629abdccec2c4754b528d70",
              lock.jar.url == "https://github.com/tlaplus/CommunityModules/releases/download/202609120237/CommunityModules-deps-202609120237.jar",
              Set(lock.modules.keys) == communityNames else {
            throw FiniteGraphCaseError.pinMismatch("CommunityModules release")
        }
        let jar = try PinnedTLCModuleJar(
            url: toolRoot.appendingPathComponent("downloads/CommunityModules-deps.jar"),
            sha256: lock.jar.sha256)
        try jar.validate()
        let basePaths = try ([base.module] + base.imports).map {
            try RetainedFiles.resolve(fixtures.appendingPathComponent($0), beneath: fixtures)
        }
        guard SHA256.hex(try Data(contentsOf: basePaths[0])) == base.moduleSHA256 else {
            throw FiniteGraphCaseError.pinMismatch("EWD998ChanID base source")
        }
        let ioUtils = toolRoot.appendingPathComponent("community-modules/IOUtils.tla")
        guard let ioUtilsSHA = lock.modules["IOUtils"],
              SHA256.hex(try Data(contentsOf: ioUtils)) == ioUtilsSHA else {
            throw FiniteGraphCaseError.pinMismatch("IOUtils.tla")
        }
        let edges: [(String, String)] = [
            ("EWD998ChanID_export", "EWD998ChanID"),
            ("EWD998ChanID_export", "IOUtils"),
            ("IOUtils", "SequencesExt")
        ] + base.dependencies.map { ($0.importingModule, $0.importedModule) }
        let dependencies = edges.enumerated().map { index, edge in
            TLAModuleBundle.ModuleDependency(importingModule: edge.0, importedModule: edge.1,
                structuralPath: [caseID, "dependencies", String(index)])
        }
        let bundle = try TLCProcessRequest.declaredBundle(
            root: module, configuration: cfg, imports: basePaths + [ioUtils],
            dependencies: dependencies)
        try bundle.validateDeclaredClosure()

        try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
        try GeneratedTLCOracle.retainGeneratedInputs(bundle,
            in: output.appendingPathComponent("reference-input"))
        let interceptor = try stageCurlInterceptor(in: output)
        let work = output.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let environment = [
            "PATH": interceptor.executable.deletingLastPathComponent().path,
            "SWIFTTLA_BLOCKED_POST_PAYLOAD": interceptor.payload.path
        ]
        let check = try FiniteGraphCase(
            id: caseID, exploration: .init(maximumStateLimit: Int.max, symmetryReduction: .disabled),
            moduleSHA256: moduleSHA, cfgSHA256: cfgSHA,
            arguments: ["-workers", "1", "-fp", "1", "-generate", "-noTE"],
            environment: environment, pin: pin)
        let request = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            supplementalJar: jar, bundle: bundle,
            graphEvents: work.appendingPathComponent("unused.bin"),
            traceOutput: work.appendingPathComponent("counterexample.json"),
            workingDirectory: work, finiteGraphCase: check, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let outcome = try process.run(request, retainingIn: output.appendingPathComponent("tlc"))
        let payload: Data? = FileManager.default.fileExists(atPath: interceptor.payload.path)
            ? try Data(contentsOf: interceptor.payload) : nil
        try RetainedFiles.writeJSON([
            "schema": "swifttla.ewd998-export-reference",
            "caseID": caseID, "result": "terminal", "tlcOutcome": String(describing: outcome),
            "modelCheckComplete": outcome == .completed,
            "moduleSHA256": moduleSHA, "cfgSHA256": cfgSHA,
            "communityJarSHA256": jar.sha256,
            "curlInterceptorSHA256": SHA256.hex(Data(curlScript.utf8)),
            "externalPostIntercepted": payload != nil,
            "interceptedPayloadSHA256": payload.map(SHA256.hex) ?? ""
        ], to: output.appendingPathComponent("report.json"))
    }
}

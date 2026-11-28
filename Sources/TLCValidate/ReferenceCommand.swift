import Foundation
import UpstreamParity
import SwiftTLA

/// Capture the published inputs before a model or Swift validation scenario exists.
func runReference(arguments: [String]) throws {
    guard arguments.count >= 9, ["capture", "compare", "compare-witness"].contains(arguments[0]), arguments[1] == "--case",
          arguments[3] == "--module", arguments[5] == "--config", arguments[7] == "--output",
          arguments[2].range(of: "^[a-z0-9_-]+$", options: .regularExpression) != nil else {
        throw ValidationCLIError.invalidManifest("reference <capture|compare|compare-witness> --case <id> --module <root.tla> --config <model.cfg> --output <new-directory> [--native <evidence-directory>] [Importer=path/to/Import.tla ...]")
    }
    let fm = FileManager.default
    let output = URL(fileURLWithPath: arguments[8], isDirectory: true)
    guard !fm.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
    let env = ProcessInfo.processInfo.environment
    _ = try requiredEnvironment("SWIFTTLA_UPSTREAM_REFERENCE_CACHE", env)
    let root = try RetainedFiles.projectRoot(URL(fileURLWithPath: fm.currentDirectoryPath))
    let toolsRoot = URL(fileURLWithPath: try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", env))
    let lock = try decode(PinnedTLCToolchain.self, at: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
    guard lock.schema == "TLCReferencePin", let archive = lock.java.archives[try normalizedArchitecture()] else {
        throw ValidationCLIError.invalidManifest("toolchain")
    }
    let pin = try referencePin(from: lock, javaArchive: archive, toolRoot: toolsRoot)
    let tools = try ResolvedTLCToolchain(toolRoot: toolsRoot, projectRoot: root, pin: pin)
    let comparing = arguments[0] == "compare"
    guard !comparing || (arguments.count >= 11 && arguments[9] == "--native") else {
        throw ValidationCLIError.invalidManifest("reference compare requires --native <evidence-directory>")
    }
    var imports: [URL] = []
    var edges: [TLAModuleBundle.ModuleDependency] = []
    let supplementalJar = try referenceCommunityJar(for: arguments[2], projectRoot: root, toolsRoot: toolsRoot)
    for argument in arguments.dropFirst(comparing ? 11 : 9) {
        let parts = argument.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { throw ValidationCLIError.invalidManifest("expected Importer=path/to/Import.tla") }
        let file = URL(fileURLWithPath: String(parts[1])).standardizedFileURL
        if !imports.contains(file) { imports.append(file) }
        edges.append(.init(importingModule: String(parts[0]), importedModule: file.deletingPathExtension().lastPathComponent,
            structuralPath: [arguments[2], "dependencies", String(edges.count)]))
    }
    let bundle = try TLCProcessRequest.declaredBundle(root: URL(fileURLWithPath: arguments[4]),
        configuration: URL(fileURLWithPath: arguments[6]), imports: imports, dependencies: edges)
    try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let timeout = TimeInterval(env["SWIFTTLA_REFERENCE_TIMEOUT_SECONDS"] ?? "600") ?? 0
    guard timeout.isFinite, timeout > 0, timeout <= 86_400 else {
        throw ValidationCLIError.invalidManifest("reference timeout must be positive and at most 24 hours")
    }
    let outcome = try GeneratedTLCOracle.run(bundle: bundle, id: arguments[2], maximumStates: 10_000_000,
        timeout: timeout, tools: tools, pin: pin, workRoot: output.deletingLastPathComponent(),
        retained: output, invocation: .finiteGraph, renderedActions: [], process: TLCProcessAdapter(),
        supplementalJar: supplementalJar, referenceCache: comparing ? .requireHit : .readThrough)
    print("reference \(arguments[2]): \(outcome)")
    if case .failed = outcome { throw UpstreamTLCParityError.invalidOutcome(String(describing: outcome)) }
    if arguments[0] == "compare-witness" {
        guard outcome == .safetyViolation,
              let entry = try modelValidationScenarios().first(where: { $0.id == arguments[2] }) else {
            throw ValidationCLIError.invalidManifest("expected an upstream safety violation and a registered scenario")
        }
        try compareReferenceWitness(entry.scenario, id: arguments[2], directory: output, tools: tools, pin: pin, timeout: timeout)
    }
    if comparing {
        guard outcome == .completed, let scenario = try modelValidationScenarios().first(where: { $0.id == arguments[2] }) else {
            throw ValidationCLIError.invalidManifest("complete TLC reference and registered native case required")
        }
        let native = URL(fileURLWithPath: arguments[10]).appendingPathComponent(arguments[2])
        let difference = try ValidationEvidenceComparison.compareNativeReferenceGraph(caseID: arguments[2],
            native: native, reference: output.appendingPathComponent("graph-events.bin.gz"),
            actions: scenario.scenario.render().actions, in: output)
        if let difference { throw ValidationCLIError.invalidManifest("graph mismatch: " + difference) }
        print("native/reference initial states and labeled graph: exact")
    }
}

private func referenceCommunityJar(for caseID: String, projectRoot: URL, toolsRoot: URL) throws -> PinnedTLCModuleJar? {
    struct Lock: Decodable {
        struct Jar: Decodable { let sha256: String }
        let schema: String
        let jar: Jar
    }
    let inputs = projectRoot.appendingPathComponent("Verification/FiniteGraph")
    let registryURL = inputs.appendingPathComponent("cases.json")
    guard FileManager.default.fileExists(atPath: registryURL.path),
          try decode(FiniteGraphManifest.self, at: registryURL).cases.contains(where: { $0.id == caseID && $0.referenceCommunityModules })
    else { return nil }
    let lock = try decode(Lock.self, at: inputs.appendingPathComponent("community-modules.json"))
    guard lock.schema == "PinnedCommunityModules" else {
        throw ValidationCLIError.invalidManifest("expected the pinned Community Modules release")
    }
    let jar = try PinnedTLCModuleJar(url: toolsRoot.appendingPathComponent("downloads/CommunityModules-deps.jar"), sha256: lock.jar.sha256)
    try jar.validate()
    return jar
}

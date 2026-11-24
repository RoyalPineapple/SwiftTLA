import Foundation
import UpstreamParity
import SwiftTLA

/// Capture the published inputs before a model or Swift validation scenario exists.
func runReference(arguments: [String]) throws {
    guard arguments.count >= 9, ["capture", "compare"].contains(arguments[0]), arguments[1] == "--case",
          arguments[3] == "--module", arguments[5] == "--config", arguments[7] == "--output",
          arguments[2].range(of: "^[a-z0-9_-]+$", options: .regularExpression) != nil else {
        throw ValidationCLIError.invalidManifest("reference capture --case <id> --module <root.tla> --config <model.cfg> --output <new-directory> [--native <evidence-directory>] [Importer=path/to/Import.tla ...]")
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
    let outcome = try GeneratedTLCOracle.run(bundle: bundle, id: arguments[2], maximumStates: 10_000_000,
        timeout: 600, tools: tools, pin: pin, workRoot: output.deletingLastPathComponent(),
        retained: output, invocation: .finiteGraph, renderedActions: [], process: TLCProcessAdapter(),
        referenceCache: comparing ? .requireHit : .readThrough)
    print("reference \(arguments[2]): \(outcome)")
    if case .failed = outcome { throw UpstreamTLCParityError.invalidOutcome(String(describing: outcome)) }
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

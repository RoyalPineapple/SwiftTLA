import Foundation
import SwiftTLA
import UpstreamParity

private enum UpstreamCommandError: Error, CustomStringConvertible {
    case usage
    case unknownCase(String)
    case invalidToolchain
    case outputExists(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: tlc-validate upstream list | upstream run --case <id-or-all> --output <directory> | upstream cache-key --case <id> | upstream annotate --case <id> --evidence <directory>"
        case .unknownCase(let id): "unknown upstream case: \(id)"
        case .invalidToolchain: "invalid pinned TLC toolchain"
        case .outputExists(let path): "output already exists: \(path)"
        }
    }
}

func runUpstream(arguments: [String]) -> Never {
    do {
        let root = try RetainedFiles.projectRoot(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let manifest = try decode(FiniteGraphManifest.self,
            at: root.appendingPathComponent("Verification/FiniteGraph/cases.json"))
        if arguments == ["list"] {
            print(String(decoding: try JSONEncoder().encode(manifest.cases.map(\.id)), as: UTF8.self))
            exit(0)
        }
        if arguments.count == 5, arguments[0] == "annotate", arguments[1] == "--case",
           arguments[3] == "--evidence" {
            guard let declaration = manifest.cases.first(where: { $0.id == arguments[2] }) else {
                throw UpstreamCommandError.unknownCase(arguments[2])
            }
            if let scenario = try declaration.resolveScenario() {
                let report = URL(fileURLWithPath: arguments[4]).standardizedFileURL
                    .appendingPathComponent(declaration.id).appendingPathComponent("comparison.json")
                try ScenarioCheckCoverage.annotateUpstream(scenario, caseID: declaration.id, reportURL: report)
            }
            exit(0)
        }
        if arguments.count == 3, arguments[0] == "cache-key", arguments[1] == "--case" {
            guard let declaration = manifest.cases.first(where: { $0.id == arguments[2] }) else {
                throw UpstreamCommandError.unknownCase(arguments[2])
            }
            let environment = ProcessInfo.processInfo.environment
            let toolRoot = URL(fileURLWithPath: try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", environment))
            let inputRoot = try requiredEnvironment("FINITE_GRAPH_INPUT_ROOT", environment)
            let lock = try decode(PinnedTLCToolchain.self,
                at: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
            guard lock.schema == "TLCReferencePin",
                  let archive = lock.java.archives[try normalizedArchitecture()] else {
                throw UpstreamCommandError.invalidToolchain
            }
            let pin = try referencePin(from: lock, javaArchive: archive, toolRoot: toolRoot)
            let rendered = try declaration.renderModel()
            let reference = try TLCProcessRequest.declaredBundle(
                root: inputPath(declaration.module, within: inputRoot),
                configuration: inputPath(declaration.configuration, within: inputRoot),
                imports: try declaration.imports.map { try inputPath($0, within: inputRoot) },
                dependencies: declaration.dependencies.enumerated().map { index, edge in
                    .init(importingModule: edge.importingModule,
                          importedModule: edge.importedModule,
                          structuralPath: [declaration.id, "dependencies", String(index)])
                })
            if let assumption = try declaration.resolveAssumptionScenario() {
                guard let expected = declaration.assumptionExpectation else {
                    throw EvidenceFormatError.invalidField(record: declaration.id, field: "assumption expectation")
                }
                print(try AssumptionValidationEvidence.upstreamCacheKey(
                    id: declaration.id, scenario: assumption, reference: reference,
                    expectedModuleSHA256: declaration.moduleSHA256,
                    expectedCFGSHA256: declaration.cfgSHA256,
                    expectedVerdict: expected,
                    maximumStates: declaration.exploration.maximumStateLimit, pin: pin))
            } else {
                print(try UpstreamTLCParity.cacheKey(id: declaration.id, rendered: rendered,
                    reference: reference, expectedModuleSHA256: declaration.moduleSHA256,
                    expectedCFGSHA256: declaration.cfgSHA256,
                    maximumStates: declaration.exploration.maximumStateLimit,
                    decisive: declaration.comparisonMode == .decisiveCounterexample, pin: pin))
            }
            exit(0)
        }
        guard arguments.count == 5, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--output" else { throw UpstreamCommandError.usage }
        let selected = manifest.cases.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty else { throw UpstreamCommandError.unknownCase(arguments[2]) }
        let output = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw UpstreamCommandError.outputExists(output.path)
        }
        let environment = ProcessInfo.processInfo.environment
        let toolRoot = URL(fileURLWithPath: try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", environment))
        let inputRoot = try requiredEnvironment("FINITE_GRAPH_INPUT_ROOT", environment)
        let lock = try decode(PinnedTLCToolchain.self,
            at: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin",
              let archive = lock.java.archives[try normalizedArchitecture()] else {
            throw UpstreamCommandError.invalidToolchain
        }
        let pin = try referencePin(from: lock, javaArchive: archive, toolRoot: toolRoot)
        let tools = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: root, pin: pin)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures = 0
        for declaration in selected {
            do {
                let rendered = try declaration.renderModel()
                let reference = try TLCProcessRequest.declaredBundle(
                    root: inputPath(declaration.module, within: inputRoot),
                    configuration: inputPath(declaration.configuration, within: inputRoot),
                    imports: try declaration.imports.map { try inputPath($0, within: inputRoot) },
                    dependencies: declaration.dependencies.enumerated().map { index, edge in
                        .init(importingModule: edge.importingModule,
                              importedModule: edge.importedModule,
                              structuralPath: [declaration.id, "dependencies", String(index)])
                    })
                if let assumption = try declaration.resolveAssumptionScenario() {
                    guard let expected = declaration.assumptionExpectation else {
                        throw EvidenceFormatError.invalidField(record: declaration.id, field: "assumption expectation")
                    }
                    let report = try AssumptionValidationEvidence.compareUpstream(
                        id: declaration.id, scenario: assumption, reference: reference,
                        expectedModuleSHA256: declaration.moduleSHA256,
                        expectedCFGSHA256: declaration.cfgSHA256,
                        expectedVerdict: expected,
                        maximumStates: declaration.exploration.maximumStateLimit,
                        timeout: declaration.timeoutSeconds, tools: tools, pin: pin,
                        to: output.appendingPathComponent(declaration.id))
                    print("upstream \(declaration.id): \(report.result)")
                    if report.result != "exact" { failures += 1 }
                } else {
                    let report = try UpstreamTLCParity.run(
                        id: declaration.id, rendered: rendered, reference: reference,
                        expectedModuleSHA256: declaration.moduleSHA256,
                        expectedCFGSHA256: declaration.cfgSHA256,
                        maximumStates: declaration.exploration.maximumStateLimit,
                        timeout: declaration.timeoutSeconds,
                        decisive: declaration.comparisonMode == .decisiveCounterexample,
                        tools: tools, pin: pin, to: output.appendingPathComponent(declaration.id),
                        spoolExecutable: validationExecutableURL())
                    print("upstream \(declaration.id): \(report.result)")
                    if report.result != "exact" { failures += 1 }
                }
            } catch {
                failures += 1
                fputs("upstream \(declaration.id): \(error)\n", stderr)
            }
        }
        exit(failures == 0 ? 0 : 2)
    } catch {
        fputs("upstream: \(error)\n", stderr)
        exit(2)
    }
}

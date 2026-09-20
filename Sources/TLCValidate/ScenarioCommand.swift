import Foundation
import SwiftTLA
import UpstreamParity

func runScenarios(arguments: [String]) -> Never {
    do {
        let scenarios = try modelValidationScenarios()
        if arguments == ["list"] {
            print(String(decoding: try JSONEncoder().encode(scenarios.map(\.id)), as: UTF8.self))
            exit(0)
        }
        guard arguments.count == 5, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--output", !arguments[4].isEmpty else {
            throw EvidenceFormatError.invalidField(record: "scenarios",
                field: "usage: scenarios list | scenarios run --case <id-or-all> --output <directory>")
        }
        let selected = scenarios.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty else {
            throw EvidenceFormatError.invalidField(record: "scenarios", field: "unknown scenario: \(arguments[2])")
        }
        fputs("scenarios: selected \(selected.count) case(s) for \(arguments[2])\n", stderr)
        let root = try RetainedFiles.projectRoot(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let toolRoot = URL(fileURLWithPath: try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", ProcessInfo.processInfo.environment))
        let output = try RetainedFiles.outputDirectory(URL(fileURLWithPath: arguments[4]), beneath: root)
        let lock = try decode(PinnedTLCToolchain.self, at: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin", let archive = lock.java.archives[try normalizedArchitecture()] else {
            throw FiniteGraphCLIError.invalidManifest("unsupported toolchain or architecture")
        }
        let pin = try referencePin(from: lock, javaArchive: archive, toolRoot: toolRoot)
        let tools = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: root, pin: pin)
        let environment = ProcessInfo.processInfo.environment
        guard let maximumStates = Int(environment["SWIFTTLA_SCENARIO_MAXIMUM_STATES"] ?? "1000"), maximumStates > 0,
              let timeout = TimeInterval(environment["SWIFTTLA_SCENARIO_TIMEOUT_SECONDS"] ?? "120"),
              timeout.isFinite, timeout > 0 else {
            throw EvidenceFormatError.invalidField(record: "scenarios", field: "positive state limit and timeout")
        }
        var failed = false
        for (id, scenario) in selected {
            let directory = output.appendingPathComponent(id)
            let started = ContinuousClock.now
            do {
                fputs("scenario \(id): native-scenario at \(started.duration(to: .now))\n", stderr)
                let run = try NativeScenarioRun(scenario, maximumStates: maximumStates)
                fputs("scenario \(id): request-preparation at \(started.duration(to: .now))\n", stderr)
                let bundle: TLAModuleBundle
                let invocation: TLCInvocationKind
                switch run.native {
                case .exhausted:
                    bundle = try run.native.rendered.tlaBundle(checking: [], checkDeadlock: false)
                    invocation = .finiteGraph
                case .counterexample:
                    bundle = run.native.rendered.tlaBundle
                    invocation = .propertyCheck
                }
                let work = try RetainedFiles.createDirectory(output.appendingPathComponent("work-\(id)"), beneath: output)
                let launch = try FiniteGraphCase(id: scenario.name,
                    exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
                    moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)), cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
                    arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: pin,
                    renderedActions: run.native.rendered.actions)
                let request = TLCProcessRequest(javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
                    bundle: bundle, graphEvents: work.appendingPathComponent("events.jsonl"),
                    traceOutput: work.appendingPathComponent("counterexample.json"), workingDirectory: work,
                    finiteGraphCase: launch, runID: UUID(), timeout: timeout, invocation: invocation,
                    referenceArtifacts: tools.artifacts)
                fputs("scenario \(id): comparison-and-retention at \(started.duration(to: .now))\n", stderr)
                try TLCScenarioCheck().run(run, request: request, in: directory)
                print("scenario \(id) (\(scenario.name)): exact")
            } catch {
                failed = true
                try RetainedFiles.createDirectory(directory, beneath: output)
                try RetainedFiles.writeText(String(describing: error), to: directory.appendingPathComponent("scenario-error.txt"))
                fputs("scenario \(id) (\(scenario.name)): \(error)\n", stderr)
            }
        }
        exit(failed ? 2 : 0)
    } catch {
        fputs("scenarios: \(error)\n", stderr)
        exit(2)
    }
}

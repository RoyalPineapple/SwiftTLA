import SwiftTLA
import UpstreamParity
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "core-conformance" {
    runCoreConformance(arguments: Array(args.dropFirst()))
}

guard let name = args.first else {
    fputs("""
    Usage: tlc-validate <name>
      operators: arithmetic comparison logic sets tuples records functions casexpr choose forall
      parity:    list | <ParityCatalog id>
      oracle:    symmetric-collections (alias: symmetric-oracle)
    """, stderr)
    exit(1)
}

private struct CoreConformanceManifest: Decodable {
    let schema: String
    let cases: [Entry]

    struct Entry: Decodable {
        struct IdentityMapping: Decodable {
            let variables: [String: String]
            let actions: [String: String]
        }

        let id: String
        let swiftSpec: String
        let module: String
        let configuration: String
        let moduleSHA256: String
        let cfgSHA256: String
        let arguments: [String]
        let argumentsSHA256: String
        let workers: Int
        let fingerprintPolynomial: Int
        let deadlock: Bool
        let replay: String
        let expectedExit: Int?
        let identityMapping: IdentityMapping
    }
}

private struct CoreConformanceToolchain: Decodable {
    let schema: String
    let tlc: TLC
    let java: Java
    let bridge: Bridge

    struct TLC: Decodable {
        let tag: String
        let commit: String
        let jar: Artifact
    }

    struct Java: Decodable {
        let distribution: String
        let version: String
        let archives: [String: Artifact]
    }

    struct Bridge: Decodable {
        let `class`: String
        let source: String
        let sourceSha256: String
        let binarySha256: String
    }

    struct Artifact: Decodable {
        let url: String
        let sha256: String
    }
}

private enum CoreConformanceCLIError: Error, CustomStringConvertible {
    case usage
    case missingEnvironment(String)
    case missingFile(String)
    case invalidManifest(String)
    case unknownCase(String)
    case outputExists(String)
    case unsupportedSwiftSpec(String)
    case invalidReplayPolicy(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate core-conformance run --case <case-or-all> --output <directory>"
        case .missingEnvironment(let name):
            return "core-conformance is not set up: missing \(name)"
        case .missingFile(let path):
            return "core-conformance prerequisite is missing: \(path)"
        case .invalidManifest(let reason):
            return "invalid core-conformance manifest: \(reason)"
        case .unknownCase(let id):
            return "unknown core-conformance case: \(id)"
        case .outputExists(let path):
            return "output directory already exists: \(path)"
        case .unsupportedSwiftSpec(let id):
            return "unsupported Swift core-conformance spec: \(id)"
        case .invalidReplayPolicy(let policy):
            return "invalid core-conformance replay policy: \(policy)"
        }
    }
}

private func runCoreConformance(arguments: [String]) -> Never {
    do {
        guard arguments.first == "run" else { throw CoreConformanceCLIError.usage }
        let options = try parseCoreConformanceOptions(Array(arguments.dropFirst()))
        let environment = ProcessInfo.processInfo.environment
        let casesPath = try requiredEnvironment("CORE_CONFORMANCE_CASES", environment)
        let manifest = try decode(CoreConformanceManifest.self, at: URL(fileURLWithPath: casesPath))
        guard manifest.schema == "CoreConformanceCasesV1" else {
            throw CoreConformanceCLIError.invalidManifest("unsupported schema")
        }
        let selected: [CoreConformanceManifest.Entry]
        if options.caseID == "all" {
            guard !manifest.cases.isEmpty else {
                throw CoreConformanceCLIError.invalidManifest("contains no cases")
            }
            selected = manifest.cases
        } else if let entry = manifest.cases.first(where: { $0.id == options.caseID }) {
            selected = [entry]
        } else {
            throw CoreConformanceCLIError.unknownCase(options.caseID)
        }
        for entry in selected {
            try validateIdentityMapping(entry.identityMapping, for: try swiftSpec(entry.swiftSpec), caseID: entry.id)
        }
        let toolRoot = try requiredEnvironment("CORE_CONFORMANCE_TOOL_ROOT", environment)
        let inputRoot = try requiredEnvironment("CORE_CONFORMANCE_INPUT_ROOT", environment)

        let output = URL(fileURLWithPath: options.output).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CoreConformanceCLIError.outputExists(output.path)
        }
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let lock = try decode(
            CoreConformanceToolchain.self,
            at: projectRoot.appendingPathComponent("Verification/CoreConformance/toolchain.json"))
        guard lock.schema == "TLCReferencePinV1" else {
            throw CoreConformanceCLIError.invalidManifest("unsupported toolchain schema")
        }
        let architecture = try normalizedArchitecture()
        guard let javaArchive = lock.java.archives[architecture] else {
            throw CoreConformanceCLIError.invalidManifest("no locked archive for \(architecture)")
        }
        let pin = try TLCReferencePinV1(
            tag: lock.tlc.tag,
            commit: lock.tlc.commit,
            jarSHA256: lock.tlc.jar.sha256,
            javaDistribution: lock.java.distribution,
            javaVersion: lock.java.version,
            javaArchiveSHA256: javaArchive.sha256,
            bridgeClass: lock.bridge.class,
            bridgeSourceSHA256: lock.bridge.sourceSha256,
            bridgeBinarySHA256: lock.bridge.binarySha256
        )

        let toolDirectory = URL(fileURLWithPath: toolRoot)
        let jar = toolDirectory.appendingPathComponent("downloads/tla2tools.jar")
        let java = toolDirectory.appendingPathComponent("java-\(architecture)/Contents/Home/bin/java")
        let bridgeClasses = toolDirectory.appendingPathComponent("bridge-classes")
        let javaArchivePath = toolDirectory.appendingPathComponent(
            "downloads/temurin-\(architecture).tar.gz")
        let bridgeSource = projectRoot.appendingPathComponent(lock.bridge.source)
        for artifact in [jar, java, bridgeClasses, javaArchivePath, bridgeSource] where
            !FileManager.default.fileExists(atPath: artifact.path)
        {
            throw CoreConformanceCLIError.missingFile(artifact.path)
        }
        let referenceArtifacts = try TLCReferenceInspectorV1.inspect(
            artifacts: TLCReferenceArtifactsV1(
                jar: jar,
                javaArchive: javaArchivePath,
                bridgeSource: bridgeSource,
                bridgeBinary: bridgeClasses
                    .appendingPathComponent(pin.bridgeClass.replacingOccurrences(of: ".", with: "/"))
                    .appendingPathExtension("class"),
                jarManifest: "",
                runtime: TLCJavaRuntimeIdentityV1(
                    version: "", vendor: "", architecture: architecture, properties: [:]
                )
            ),
            javaExecutable: java,
            directory: projectRoot
        )
        try pin.validate(referenceArtifacts)

        let runRoot = output.deletingLastPathComponent().appendingPathComponent(
            ".core-conformance-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        if selected.count > 1 {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        }

        var exitCode: Int32 = CoreConformanceExitCodeV1.exact.rawValue
        for entry in selected {
            let expectedExit = Int32(entry.expectedExit ?? Int(CoreConformanceExitCodeV1.exact.rawValue))
            guard expectedExit == CoreConformanceExitCodeV1.exact.rawValue ||
                expectedExit == CoreConformanceExitCodeV1.semanticDifference.rawValue
            else {
                throw CoreConformanceCLIError.invalidManifest(
                    "unsupported expected exit \(expectedExit) for \(entry.id)")
            }
            let caseOutput = selected.count == 1
                ? output
                : output.appendingPathComponent(entry.id, isDirectory: true)
            let declaredCase = try declaredCase(entry, pin: pin, architecture: architecture)
            let request = TLCProcessRequestV1(
                javaExecutable: java,
                jar: jar,
                bridgeClasses: bridgeClasses,
                module: try inputPath(entry.module, within: inputRoot),
                configuration: try inputPath(entry.configuration, within: inputRoot),
                graphEvents: runRoot.appendingPathComponent("\(entry.id).events.jsonl"),
                traceOutput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                replayInput: runRoot.appendingPathComponent("\(entry.id).counterexample.json"),
                workingDirectory: runRoot,
                arguments: entry.arguments,
                expectedCase: declaredCase,
                runID: UUID(),
                referencePin: pin,
                referenceArtifacts: referenceArtifacts
            )
            let result = CoreConformanceRunnerV1().run(
                case: declaredCase,
                swiftExploration: {
                    SwiftExplorationEvidenceV1(
                        caseID: declaredCase.id,
                        exploration: try ModelChecker(spec: try swiftSpec(entry.swiftSpec)).explore()
                    )
                },
                tlcRequest: request,
                replay: try replayPolicy(entry.replay),
                outputDirectory: caseOutput
            )
            if let diagnostic = result.diagnostic {
                fputs("core-conformance \(entry.id): \(diagnostic.phase.rawValue): \(diagnostic.code)\n", stderr)
            } else {
                print("core-conformance \(entry.id): \(result.exitCode.rawValue) \(result.evidenceDirectory?.path ?? "")")
            }
            if selected.count == 1 {
                exitCode = result.exitCode.rawValue
            } else if result.exitCode.rawValue != expectedExit {
                exitCode = max(exitCode, result.exitCode.rawValue)
            }
        }
        exit(exitCode)
    } catch {
        fputs("core-conformance: \(error)\n", stderr)
        exit(CoreConformanceExitCodeV1.failure.rawValue)
    }
}

private func validateIdentityMapping(
    _ mapping: CoreConformanceManifest.Entry.IdentityMapping,
    for spec: TLASpec,
    caseID: String
) throws {
    try validateIdentityMapping(
        mapping.variables,
        expectedNames: Set(spec.variables.map(\.name)),
        kind: "variable",
        caseID: caseID
    )
    try validateIdentityMapping(
        mapping.actions,
        expectedNames: Set(spec.actions.map(\.name)),
        kind: "action",
        caseID: caseID
    )
}

private func validateIdentityMapping(
    _ mapping: [String: String],
    expectedNames: Set<String>,
    kind: String,
    caseID: String
) throws {
    guard Set(mapping.keys) == expectedNames,
          Set(mapping.values) == expectedNames,
          mapping.allSatisfy({ $0.key == $0.value })
    else {
        throw CoreConformanceCLIError.invalidManifest(
            "case \(caseID) has an incomplete or non-identity \(kind) mapping"
        )
    }
}

private func parseCoreConformanceOptions(_ arguments: [String]) throws -> (caseID: String, output: String) {
    var caseID: String?
    var output: String?
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        switch option {
        case "--case" where caseID == nil:
            caseID = arguments[index + 1]
        case "--output" where output == nil:
            output = arguments[index + 1]
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let caseID, !caseID.isEmpty, let output, !output.isEmpty else {
        throw CoreConformanceCLIError.usage
    }
    return (caseID, output)
}

private func requiredEnvironment(_ name: String, _ environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw CoreConformanceCLIError.missingEnvironment(name)
    }
    return value
}

private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CoreConformanceCLIError.missingFile(url.path)
    }
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

private func normalizedArchitecture() throws -> String {
    var information = utsname()
    uname(&information)
    let architecture = withUnsafePointer(to: &information.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    switch architecture {
    case "arm64", "aarch64": return "arm64"
    case "x86_64", "amd64": return "x86_64"
    default: throw CoreConformanceCLIError.invalidManifest("unsupported architecture \(architecture)")
    }
}

private func declaredCase(
    _ entry: CoreConformanceManifest.Entry,
    pin: TLCReferencePinV1,
    architecture: String
) throws -> CoreConformanceCaseV1 {
    try CoreConformanceCaseV1(
        id: entry.id,
        moduleSHA256: entry.moduleSHA256,
        cfgSHA256: entry.cfgSHA256,
        arguments: entry.arguments,
        argumentsSHA256: entry.argumentsSHA256,
        workers: entry.workers,
        fingerprintPolynomial: entry.fingerprintPolynomial,
        deadlock: entry.deadlock,
        operatingSystem: "macos",
        architecture: architecture,
        environment: [:],
        pin: pin
    )
}

private func inputPath(_ relativePath: String, within root: String) throws -> URL {
    guard !relativePath.hasPrefix("/") else {
        throw CoreConformanceCLIError.invalidManifest("input paths must be relative")
    }
    let rootURL = URL(fileURLWithPath: root).standardizedFileURL
    let path = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    guard path.path.hasPrefix(rootURL.path + "/") else {
        throw CoreConformanceCLIError.invalidManifest("input path escapes the pinned checkout")
    }
    return path
}

private func swiftSpec(_ identifier: String) throws -> TLASpec {
    switch identifier {
    case "hour-clock": return Example.hourClock.spec
    case "die-hard-type-ok": return Example.dieHardTypeOK.spec
    default: throw CoreConformanceCLIError.unsupportedSwiftSpec(identifier)
    }
}

private func replayPolicy(_ value: String) throws -> TLCReplayPolicyV1 {
    switch value {
    case "none": return .none
    case "required": return .required
    default: throw CoreConformanceCLIError.invalidReplayPolicy(value)
    }
}


if name == "check-all" {
    var ok = 0; var fail = 0
    print("=== SwiftTLA ModelChecker vs TLC ===")
    for entry in Example.all {
        let mc = ModelChecker(spec: entry.spec, maxStates: 50000)
        do {
            let count = try mc.exploreGraph().states.count
            let result = try mc.check()
            let match = count == entry.expectedDistinct && { if case .ok = result { true } else { false } }()
            if match {
                print("OK   \(entry.id) — \(count) states")
                ok += 1
            } else {
                print("FAIL \(entry.id) — got \(count), TLC=\(entry.expectedDistinct), \(result)")
                fail += 1
            }
        } catch {
            print("ERR  \(entry.id) — \(error)")
            fail += 1
        }
    }
    print("=== \(ok) passed, \(fail) failed, 0 skipped ===")
    exit(fail > 0 ? 1 : 0)
}


if name == "bundle" {
    guard let id = args.count >= 2 ? args[1] : nil else { exit(1) }
    guard let entry = Example.all.first(where: { $0.id == id }) else { exit(1) }
    let b = entry.spec.tlaBundle
    print("=== TLA ===")
    print(b.tla)
    print("=== CFG ===")
    print(b.cfg)
    exit(0)
}


if name == "test-game-of-life" || name == "test-lazy" {
    let spec = Example.gameOfLife.spec
    let mc = ModelChecker(spec: spec, maxStates: 100)
    do { let r = try mc.check(); print("OK: \(r)") }
    catch { print("ERR: \(error)") }
    exit(0)
}

if name == "symmetric-collections" || name == "symmetric-oracle" {
    do {
        try runSymmetricCollectionOracle()
    } catch {
        fputs("Symmetric collection TLC oracle failed: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

if name == "list" {
    for e in Example.all {
        print("\(e.id)\t\(e.expectedDistinct)\t\(e.notes)")
    }
    exit(0)
}

let output: String

switch name {
case "arithmetic":
    let x = Var<Int>("x")
    output = TLASpec("arithmetic") {
        Variable(x, 0)
        Action("add") { x.becomes(x + 1).when(x < 2) }
        Action("sub") { x.becomes(x - 1).when(x > 0) }
        Action("mul") { x.becomes(x * 2).when(x == 1) }
        Action("div") { x.becomes(x / 2).when(x == 2) }
        Action("mod") { x.becomes(x % 3).when(x == 0) }
        Action("neg") { x.becomes(-x).when(x == 1) }
    }.tlaModule

case "comparison":
    let x = Var<Int>("x")
    output = TLASpec("comparison") {
        Variable(x, 0)
        Action("eq") { x.becomes(1).when(x == 0) }
        Action("neq") { x.becomes(2).when(x != 0) || x.becomes(0).when(x == 1) }
        Action("lt") { x.becomes(3).when(x < 2) }
        Action("gt") { x.becomes(4).when(x > 1) || x.becomes(0).when(x == 3) }
    }.tlaModule

case "logic":
    let a = Var<Bool>("a")
    let b = Var<Bool>("b")
    output = TLASpec("logic") {
        Variable(a, false); Variable(b, false)
        Action("toggle") {
            (a == false) && (b == false) && a.becomes(true) ||
            (a == true) && a.becomes(false) && b.becomes(true)
        }
    }.tlaModule

case "sets":
    let s = Var<TLASetType>("s")
    output = TLASpec("sets") {
        Variable(s, TLAValue.set([.int(0), .int(1)]))
        Action("remove") {
            s.cardinality > 0
                && s.becomes(s.subtracting(StateExpr.singleton(0))).when(s.cardinality == 2)
        }
        Action("shrink") {
            s.cardinality == 1 && s.becomes(StateExpr.setLiteral([]))
        }
    }.tlaModule

case "tuples":
    let val = Var<Int>("val")
    output = TLASpec("tuples") {
        Variable(val, 0)
        Action("set") { val.becomes(StateExpr.tuple([1, 2]).count).when(val == 0) }
        Action("access") { val.becomes(StateExpr.tuple([5, 6]).at(1)).when(val == 2) }
    }.tlaModule

case "records":
    let r = Var<Int>("r")
    output = TLASpec("records") {
        Variable(r, 0)
        Action("set") {
            r.becomes(StateExpr.record(["a": 3, "b": 7]).domain.cardinality).when(r == 0)
        }
    }.tlaModule

case "functions":
    let f = Var<Int>("f")
    output = TLASpec("functions") {
        Variable(f, 0)
        Action("apply") {
            f.becomes(StateExpr.function(domain: StateExpr.set([1]), 42).applying(1)).when(f == 0)
        }
    }.tlaModule

case "casexpr":
    let x = Var<Int>("x")
    output = TLASpec("casexpr") {
        Variable(x, 0)
        Action("classify") {
            x.becomes(StateExpr.firstMatch(
                (when: x == 0, then: 10),
                (when: x == 1, then: 20),
                fallback: 99
            )).when(x < 2)
        }
    }.tlaModule

case "choose":
    let picked = Var<Int>("picked")
    let q = Var<TLASetType>("q")
    output = TLASpec("choose") {
        Variable(picked, 0)
        Variable(q, TLAValue.set([.int(0), .int(1)]))
        Action("pick") {
            q.cardinality > 0
                && choose(picked, from: q)
                && q.becomes(q.subtracting(StateExpr.singleton(picked)))
        }
    }.tlaModule

case "forall":
    let ok = Var<Bool>("ok")
    let s = StateExpr.set([1, 2])
    output = TLASpec("forall") {
        Variable(ok, false)
        Action("check") { StateExpr.for(allIn: s, 1 >= 0) && ok.becomes(true) }
    }.tlaModule

default:
    if let entry = Example.all.first(where: { $0.id == name }) {
        output = entry.spec.tlaModule
    } else {
        fputs("Unknown spec: \(name)\n", stderr)
        fputs("Run: tlc-validate list\n", stderr)
        exit(1)
    }
}

print(output, terminator: "")

private struct OracleDevice: Identifiable {
    let id: Int
}

private struct TLCExecution {
    let status: Int32
    let output: String

    var distinctStates: Int? {
        let expression = try? NSRegularExpression(
            pattern: "([0-9]+) distinct states (?:found|generated)",
            options: []
        )
        guard let match = expression?.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ),
        let range = Range(match.range(at: 1), in: output)
        else { return nil }
        return Int(output[range])
    }
}

private enum SymmetricCollectionOracleError: Error, CustomStringConvertible {
    case missingTLCJar(String)
    case missingJavaRuntime([String])
    case missingStateCount(String)
    case swiftTLCMismatch(scope: Int, swift: Int, tlc: Int)
    case quotedStringControlAccepted(String)

    var description: String {
        switch self {
        case .missingTLCJar(let path):
            return "TLC jar not found at \(path); run scripts/setup-tlc.sh or set TLA_TOOLS_JAR."
        case .missingJavaRuntime(let candidates):
            let checked = candidates.joined(separator: ", ")
            return "No executable Java runtime found for TLC. Checked \(checked); set TLC_JAVA or JAVA_HOME, "
                + "or install the repository-configured OpenJDK 21."
        case .missingStateCount(let output):
            return "TLC did not report its distinct-state count:\n\(output)"
        case .swiftTLCMismatch(let scope, let swift, let tlc):
            return "scope \(scope): Swift checker found \(swift) orbit states but TLC found \(tlc)."
        case .quotedStringControlAccepted(let output):
            return "quoted-string symmetry control unexpectedly succeeded:\n\(output)"
        }
    }
}

private func runSymmetricCollectionOracle() throws {
    let jarPath = ProcessInfo.processInfo.environment["TLA_TOOLS_JAR"]
        ?? FileManager.default.currentDirectoryPath + "/.build/tla-tools/tla2tools.jar"
    guard FileManager.default.fileExists(atPath: jarPath) else {
        throw SymmetricCollectionOracleError.missingTLCJar(jarPath)
    }

    for scope in 2...4 {
        let spec = symmetricOracleSpec(scope: scope)
        let swiftStates = try ModelChecker(spec: spec).exploreGraph().states.count
        let execution = try executeTLC(bundle: spec.tlaBundle, moduleName: spec.name, jarPath: jarPath)
        guard let tlcStates = execution.distinctStates else {
            throw SymmetricCollectionOracleError.missingStateCount(execution.output)
        }
        guard execution.status == 0, tlcStates == swiftStates else {
            throw SymmetricCollectionOracleError.swiftTLCMismatch(
                scope: scope,
                swift: swiftStates,
                tlc: tlcStates
            )
        }
        print("OK   symmetric scope \(scope) — Swift/TLC \(swiftStates) orbit states")
    }

    let control = quotedStringSymmetryControl(scope: 2)
    let execution = try executeTLC(bundle: control, moduleName: "SymmetricOracle2", jarPath: jarPath)
    guard execution.status != 0 else {
        throw SymmetricCollectionOracleError.quotedStringControlAccepted(execution.output)
    }
    print("OK   quoted-string symmetry control rejected by TLC")
}

private func symmetricOracleSpec(scope: Int) -> TLASpec {
    let devices = DictionaryVar<OracleDevice, Int>("devices", scope: scope)
    return TLASpec("SymmetricOracle\(scope)") {
        devices
        CollectionAction("advance", on: devices) { member in
            devices[member] == 0 && devices.update(member, to: 1)
        }
        Invariant("ValidPhase") { devices.allSatisfy { $0 == 0 || $0 == 1 } }
    }
}

private func quotedStringSymmetryControl(scope: Int) -> (tla: String, cfg: String) {
    let bundle = symmetricOracleSpec(scope: scope).tlaBundle
    let members = (0..<scope).map { "DevicesMember\($0)" }
    var tla = bundle.tla.replacingOccurrences(
        of: "CONSTANTS \(members.joined(separator: ", "))\n",
        with: ""
    )
    for member in members {
        tla = tla.replacingOccurrences(of: member, with: "\"\(member)\"")
    }
    let cfg = bundle.cfg
        .split(separator: "\n")
        .filter { !$0.hasPrefix("CONSTANT ") }
        .joined(separator: "\n") + "\n"
    return (tla, cfg)
}

private func executeTLC(
    bundle: (tla: String, cfg: String),
    moduleName: String,
    jarPath: String
) throws -> TLCExecution {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftTLA-TLC-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let tlaURL = directory.appendingPathComponent("\(moduleName).tla")
    let cfgURL = directory.appendingPathComponent("\(moduleName).cfg")
    try bundle.tla.write(to: tlaURL, atomically: true, encoding: .utf8)
    try bundle.cfg.write(to: cfgURL, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: try resolveTLCJava())
    process.arguments = ["-cp", jarPath, "tlc2.TLC", "-nowarning", "-config", cfgURL.path, tlaURL.path]
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return TLCExecution(status: process.terminationStatus, output: output)
}

private func resolveTLCJava() throws -> String {
    let environment = ProcessInfo.processInfo.environment
    var candidates = [String]()
    if let java = environment["TLC_JAVA"] {
        candidates.append(java)
    }
    if let javaHome = environment["JAVA_HOME"] {
        candidates.append("\(javaHome)/bin/java")
    }
    candidates += [
        "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java",
        "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
    ]
    if let path = environment["PATH"] {
        candidates += path.split(separator: ":").map { "\($0)/java" }
    }
    if let java = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
        return java
    }
    throw SymmetricCollectionOracleError.missingJavaRuntime(candidates)
}

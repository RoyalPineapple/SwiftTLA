import SwiftTLA
import UpstreamParity
import Foundation

struct CoreSupportGateOptions {
    let evidence: String
    let report: String
    let gateRunID: UUID
    let prerequisiteAvailable: Bool
    let conformanceExitCode: Int32
}

func validateMappings(
    _ entry: CoreConformanceCasesManifest.Entry,
    for spec: TLASpec
) throws -> [String: String] {
    let mapping = entry.identityMapping
    try validateIdentityMapping(
        mapping.variables,
        expectedNames: Set(spec.variables.map(\.name)),
        kind: "variable",
        caseID: entry.id
    )
    try validateIdentityMapping(
        mapping.actions,
        expectedNames: Set(spec.actions.map(\.name)),
        kind: "action",
        caseID: entry.id
    )
    let expected = spec.actions.flatMap(invocationMappings)
    guard expected.isEmpty == entry.invocationMappings.isEmpty else {
        throw CoreConformanceCLIError.invalidManifest(
            "case \(entry.id) must declare every parameterized action wrapper")
    }
    guard expected.count == entry.invocationMappings.count,
          zip(expected, entry.invocationMappings).allSatisfy({ expected, declared in
              expected.wrapper == declared.wrapper
                && expected.action == declared.action
                && expected.arguments == declared.arguments
                && expected.indices == declared.indices
          })
    else {
        throw CoreConformanceCLIError.invalidManifest(
            "case \(entry.id) has incomplete or reordered invocation wrapper provenance")
    }
    return Dictionary(uniqueKeysWithValues: entry.invocationMappings.map {
        ($0.runtimeValue.swiftLabel, $0.wrapper)
    })
}

func invocationMappings(
    for action: NamedAction
) -> [CoreConformanceCasesManifest.Entry.InvocationMapping] {
    func expand(
        _ position: Int,
        _ arguments: [String],
        _ indices: [Int]
    ) -> [CoreConformanceCasesManifest.Entry.InvocationMapping] {
        guard position < action.bindings.count else {
            guard !indices.isEmpty else { return [] }
            let wrapper = "\(action.name)__\(indices.map(String.init).joined(separator: "_"))"
            return [try! CoreConformanceCasesManifest.Entry.InvocationMapping(
                wrapper: wrapper,
                action: action.name,
                arguments: arguments,
                indices: indices)]
        }
        return action.bindings[position].values.enumerated().flatMap { index, value in
            expand(position + 1, arguments + [value.description], indices + [index])
        }
    }
    return expand(0, [], [])
}

func validateIdentityMapping(
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

func parseCoreConformanceOptions(
    _ arguments: [String]
) throws -> (caseID: String, output: String, gateRunID: UUID?) {
    var caseID: String?
    var output: String?
    var gateRunID: UUID?
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        switch option {
        case "--case" where caseID == nil:
            caseID = arguments[index + 1]
        case "--output" where output == nil:
            output = arguments[index + 1]
        case "--run-id" where gateRunID == nil:
            guard let value = UUID(uuidString: arguments[index + 1]) else {
                throw CoreConformanceCLIError.invalidGateRunID(arguments[index + 1])
            }
            gateRunID = value
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let caseID, !caseID.isEmpty, let output, !output.isEmpty else {
        throw CoreConformanceCLIError.usage
    }
    return (caseID, output, gateRunID)
}

func parseCoreSupportGateOptions(_ arguments: [String]) throws -> CoreSupportGateOptions {
    var evidence: String?
    var report: String?
    var gateRunID: UUID?
    var prerequisiteAvailable = true
    var conformanceExitCode = CoreConformanceExitCode.exact.rawValue
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        let value = arguments[index + 1]
        switch option {
        case "--evidence" where evidence == nil:
            evidence = value
        case "--report" where report == nil:
            report = value
        case "--run-id" where gateRunID == nil:
            guard let parsed = UUID(uuidString: value) else {
                throw CoreConformanceCLIError.invalidGateRunID(value)
            }
            gateRunID = parsed
        case "--prerequisite":
            switch value {
            case "available": prerequisiteAvailable = true
            case "unavailable": prerequisiteAvailable = false
            default: throw CoreConformanceCLIError.invalidPrerequisite(value)
            }
        case "--conformance-exit":
            guard let parsed = Int32(value),
                  parsed == CoreConformanceExitCode.exact.rawValue
                    || parsed == CoreConformanceExitCode.semanticDifference.rawValue
                    || parsed == CoreConformanceExitCode.failure.rawValue
            else { throw CoreConformanceCLIError.invalidPrerequisite(value) }
            conformanceExitCode = parsed
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let evidence, !evidence.isEmpty,
          let report, !report.isEmpty,
          let gateRunID
    else { throw CoreConformanceCLIError.usage }
    return CoreSupportGateOptions(
        evidence: evidence,
        report: report,
        gateRunID: gateRunID,
        prerequisiteAvailable: prerequisiteAvailable,
        conformanceExitCode: conformanceExitCode)
}

func requiredEnvironment(_ name: String, _ environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw CoreConformanceCLIError.missingEnvironment(name)
    }
    return value
}

func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CoreConformanceCLIError.missingFile(url.path)
    }
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

func normalizedArchitecture() throws -> String {
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

func declaredCase(
    _ entry: CoreConformanceCasesManifest.Entry,
    pin: TLCReferencePin,
    architecture: String
) throws -> CoreConformanceCase {
    try CoreConformanceCase(
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
        pin: pin,
        governance: entry.governance,
        invocationMappings: try entry.invocationMappings.map { mapping in
            try CoreConformanceInvocationMapping(
                wrapper: mapping.wrapper,
                action: mapping.action,
                arguments: mapping.arguments,
                indices: mapping.indices)
        },
        valueNormalizations: try entry.valueNormalizations.map { normalization in
            try CoreConformanceValueNormalization(
                binding: normalization.binding,
                functionKeys: normalization.functionKeys)
        }
    )
}

func inputPath(_ relativePath: String, within root: String) throws -> URL {
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

func swiftSpec(_ identifier: String) throws -> TLASpec {
    switch identifier {
    case "hour-clock": return Example.hourClock.spec
    case "die-hard-type-ok": return Example.dieHardTypeOK.spec
    case "multicar-elevator", "multicar-elevator-edge-mismatch": return MultiCarElevator.spec
    case "simultaneous-swap": return simultaneousSwapConformanceSpec()
    default: throw CoreConformanceCLIError.unsupportedSwiftSpec(identifier)
    }
}

private func simultaneousSwapConformanceSpec() -> TLASpec {
    let left = Var<Int>("left")
    let right = Var<Int>("right")
    return TLASpec("SimultaneousSwap") {
        Variable(left, 1)
        Variable(right, 2)
        Action("Swap") {
            left.becomes(right)
            right.becomes(left)
        }
    }
}

func replayPolicy(_ value: String) throws -> TLCReplayPolicy {
    switch value {
    case "none": return .none
    case "required": return .required
    default: throw CoreConformanceCLIError.invalidReplayPolicy(value)
    }
}

struct OracleDevice: Identifiable {
    let id: Int
}

struct TLCExecution {
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

enum SymmetricCollectionOracleError: Error, CustomStringConvertible {
    case missingTLCJar(String)
    case missingJavaRuntime([String])
    case missingStateCount(String)
    case swiftTLCMismatch(scope: Int, swift: Int, tlc: Int)
    case quotedStringControlAccepted(String)

    var description: String {
        switch self {
        case .missingTLCJar(let path):
            return "TLC jar not found at \(path); set TLA_TOOLS_JAR or place tla2tools.jar at .build/tla-tools/tla2tools.jar."
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

func runSymmetricCollectionOracle() throws {
    let jarPath = ProcessInfo.processInfo.environment["TLA_TOOLS_JAR"]
        ?? FileManager.default.currentDirectoryPath + "/.build/tla-tools/tla2tools.jar"
    guard FileManager.default.fileExists(atPath: jarPath) else {
        throw SymmetricCollectionOracleError.missingTLCJar(jarPath)
    }

    for scope in 2...4 {
        let spec = symmetricOracleSpec(scope: scope)
        let compilation = try spec.compile()
        let swiftStates = try ModelChecker(compilation: compilation).exploreGraph().states.count
        let execution = try executeTLC(bundle: try compilation.renderedTLAModuleBundle(), moduleName: spec.name, jarPath: jarPath)
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

    let control = try quotedStringSymmetryControl(scope: 2)
    let execution = try executeTLC(bundle: control, moduleName: "SymmetricOracle2", jarPath: jarPath)
    guard execution.status != 0 else {
        throw SymmetricCollectionOracleError.quotedStringControlAccepted(execution.output)
    }
    print("OK   quoted-string symmetry control rejected by TLC")
}

func symmetricOracleSpec(scope: Int) -> TLASpec {
    let devices = SymmetricCollectionVar<OracleDevice, Int>("devices")
    return TLASpec("SymmetricOracle\(scope)") {
        SymmetricCollection(devices, verificationScope: scope, initial: 0)
        CollectionAction("advance", on: devices) { member in
            devices[member] == 0 && devices.update(member, to: 1)
        }
        Invariant("ValidPhase") { devices.allSatisfy { $0 == 0 || $0 == 1 } }
    }
}

func quotedStringSymmetryControl(scope: Int) throws -> TLAModuleBundle {
    let bundle = try symmetricOracleSpec(scope: scope).compile().renderedTLAModuleBundle()
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
    return TLAModuleBundle.untrusted(
        root: TLAModuleFile(name: "SymmetricOracle2", tla: tla, cfg: cfg)
    )
}

func executeTLC(
    bundle: TLAModuleBundle,
    moduleName: String,
    jarPath: String
) throws -> TLCExecution {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftTLA-TLC-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for file in bundle.files {
        let tlaURL = directory.appendingPathComponent("\(file.name).tla")
        try file.tla.write(to: tlaURL, atomically: true, encoding: .utf8)
        if let cfg = file.cfg {
            let cfgURL = directory.appendingPathComponent("\(file.name).cfg")
            try cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        }
    }
    let tlaURL = directory.appendingPathComponent("\(moduleName).tla")
    let cfgURL = directory.appendingPathComponent("\(moduleName).cfg")

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

func resolveTLCJava() throws -> String {
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

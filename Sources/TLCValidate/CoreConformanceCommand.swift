import SwiftTLA
import UpstreamParity
import Foundation

func conformanceActionCalls(
    _ compilation: CompiledSpecification
) throws -> (mappings: [CoreConformanceInvocationMapping], swiftNames: [String: String]) {
    let mappings = try compilation.renderedActionCalls().map { call in
        try CoreConformanceInvocationMapping(
            wrapper: call.renderedName,
            action: call.sourceName,
            arguments: call.arguments.map(\.description)
        )
    }
    return (
        mappings: mappings,
        swiftNames: Dictionary(uniqueKeysWithValues: mappings.map { ($0.swiftLabel, $0.wrapper) })
    )
}

func parseCoreConformanceOptions(
    _ arguments: [String]
) throws -> (caseID: String, output: String, runID: UUID?) {
    var caseID: String?
    var output: String?
    var runID: UUID?
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw CoreConformanceCLIError.usage }
        switch option {
        case "--case" where caseID == nil:
            caseID = arguments[index + 1]
        case "--output" where output == nil:
            output = arguments[index + 1]
        case "--run-id" where runID == nil:
            guard let value = UUID(uuidString: arguments[index + 1]) else {
                throw CoreConformanceCLIError.invalidRunID(arguments[index + 1])
            }
            runID = value
        default:
            throw CoreConformanceCLIError.usage
        }
        index += 2
    }
    guard let caseID, !caseID.isEmpty, let output, !output.isEmpty else {
        throw CoreConformanceCLIError.usage
    }
    return (caseID, output, runID)
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
    architecture: String,
    invocationMappings: [CoreConformanceInvocationMapping]
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
        invocationMappings: invocationMappings,
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
    let rootURL = try ConformanceEvidence.projectRoot(URL(fileURLWithPath: root))
    do {
        return try ConformanceEvidence.resolve(
            rootURL.appendingPathComponent(relativePath),
            beneath: rootURL)
    } catch {
        throw CoreConformanceCLIError.invalidManifest("input path escapes the pinned checkout")
    }
}

func swiftSpec(_ identifier: String) throws -> TLASpec {
    switch identifier {
    case "hour-clock": return Example.hourClock.spec
    case "die-hard-type-ok": return Example.dieHardTypeOK.spec
    case "multicar-elevator": return MultiCarElevator.spec
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

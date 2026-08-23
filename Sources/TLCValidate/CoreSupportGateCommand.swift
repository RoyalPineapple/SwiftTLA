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
    let expected = try spec.actions.flatMap { try invocationMappings(for: $0) }
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
    return try Dictionary(uniqueKeysWithValues: entry.invocationMappings.map {
        (try $0.runtimeValue().swiftLabel, $0.wrapper)
    })
}

func invocationMappings(
    for action: NamedAction
) throws -> [CoreConformanceCasesManifest.Entry.InvocationMapping] {
    func expand(
        _ position: Int,
        _ arguments: [String],
        _ indices: [Int]
    ) throws -> [CoreConformanceCasesManifest.Entry.InvocationMapping] {
        guard position < action.bindings.count else {
            guard !indices.isEmpty else { return [] }
            let wrapper = "\(action.name)__\(indices.map(String.init).joined(separator: "_"))"
            return [try CoreConformanceCasesManifest.Entry.InvocationMapping(
                wrapper: wrapper,
                action: action.name,
                arguments: arguments,
                indices: indices)]
        }
        return try action.bindings[position].values.enumerated().flatMap { index, value in
            try expand(position + 1, arguments + [value.description], indices + [index])
        }
    }
    return try expand(0, [], [])
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

func replayPolicy(_ value: String) throws -> TLCReplayPolicy {
    switch value {
    case "none": return .none
    case "required": return .required
    default: throw CoreConformanceCLIError.invalidReplayPolicy(value)
    }
}

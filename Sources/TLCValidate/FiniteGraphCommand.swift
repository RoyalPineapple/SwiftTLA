import SwiftTLA
import UpstreamParity
import Foundation

func parseFiniteGraphOptions(
    _ arguments: [String]
) throws -> (caseID: String, output: String, runID: UUID?) {
    var caseID: String?
    var output: String?
    var runID: UUID?
    var index = 0
    while index < arguments.count {
        let option = arguments[index]
        guard index + 1 < arguments.count else { throw FiniteGraphCLIError.usage }
        switch option {
        case "--case" where caseID == nil:
            caseID = arguments[index + 1]
        case "--output" where output == nil:
            output = arguments[index + 1]
        case "--run-id" where runID == nil:
            guard let value = UUID(uuidString: arguments[index + 1]) else {
                throw FiniteGraphCLIError.invalidRunID(arguments[index + 1])
            }
            runID = value
        default:
            throw FiniteGraphCLIError.usage
        }
        index += 2
    }
    guard let caseID, !caseID.isEmpty, let output, !output.isEmpty else {
        throw FiniteGraphCLIError.usage
    }
    return (caseID, output, runID)
}

func requiredEnvironment(_ name: String, _ environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw FiniteGraphCLIError.missingEnvironment(name)
    }
    return value
}

func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw FiniteGraphCLIError.missingFile(url.path)
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
    default: throw FiniteGraphCLIError.invalidManifest("unsupported architecture \(architecture)")
    }
}

func inputPath(_ relativePath: String, within root: String) throws -> URL {
    guard !relativePath.hasPrefix("/") else {
        throw FiniteGraphCLIError.invalidManifest("input paths must be relative")
    }
    let rootURL = try RetainedFiles.projectRoot(URL(fileURLWithPath: root))
    do {
        return try RetainedFiles.resolve(
            rootURL.appendingPathComponent(relativePath),
            beneath: rootURL)
    } catch {
        throw FiniteGraphCLIError.invalidManifest("input path escapes the pinned checkout")
    }
}

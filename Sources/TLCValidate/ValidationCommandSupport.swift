import Foundation
import UpstreamParity

enum ValidationCLIError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case missingFile(String)
    case invalidManifest(String)

    var description: String {
        switch self {
        case .missingEnvironment(let name): "missing \(name)"
        case .missingFile(let path): "missing file \(path)"
        case .invalidManifest(let reason): "invalid manifest: \(reason)"
        }
    }
}

func requiredEnvironment(_ name: String, _ environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw ValidationCLIError.missingEnvironment(name)
    }
    return value
}

func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ValidationCLIError.missingFile(url.path)
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
    default: throw ValidationCLIError.invalidManifest("unsupported architecture \(architecture)")
    }
}

func inputPath(_ relativePath: String, within root: String) throws -> URL {
    guard !relativePath.hasPrefix("/") else {
        throw ValidationCLIError.invalidManifest("input paths must be relative")
    }
    let rootURL = try RetainedFiles.projectRoot(URL(fileURLWithPath: root))
    do {
        return try RetainedFiles.resolve(rootURL.appendingPathComponent(relativePath), beneath: rootURL)
    } catch {
        throw ValidationCLIError.invalidManifest("input path escapes the pinned checkout")
    }
}

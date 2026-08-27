import Foundation

private let externalPackageBuildLock = NSLock()

func packageRoot() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
        directory.deleteLastPathComponent()
    }
    return directory
}

func withSerializedExternalPackageBuild<Value>(_ body: () throws -> Value) rethrows -> Value {
    externalPackageBuildLock.lock()
    defer { externalPackageBuildLock.unlock() }
    return try body()
}

func runSwiftPackage(_ arguments: [String]) throws -> (status: Int32, output: String) {
    try withSerializedExternalPackageBuild {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftTLA-external-package-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let outputURL = scratch.appendingPathComponent("output.log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments + ["-j", "1", "--scratch-path", scratch.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try output.synchronize()

        return (
            process.terminationStatus,
            String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
        )
    }
}

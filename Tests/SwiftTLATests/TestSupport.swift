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

func buildExternalConsumer(_ product: String) throws -> (status: Int32, output: String) {
    try executeExternalConsumer([
        "build",
        "--package-path", externalConsumerPackage.path,
        "--product", product,
        "-j", "1"
    ])
}

func runExternalConsumer(_ product: String) throws -> (status: Int32, output: String) {
    try executeExternalConsumer([
        "run",
        "--package-path", externalConsumerPackage.path,
        "-j", "1",
        product
    ])
}

private let externalConsumerPackage = packageRoot()
    .appendingPathComponent("Tests/Fixtures/ExternalConsumerContracts")

private func executeExternalConsumer(
    _ arguments: [String]
) throws -> (status: Int32, output: String) {
    try withSerializedExternalPackageBuild {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}

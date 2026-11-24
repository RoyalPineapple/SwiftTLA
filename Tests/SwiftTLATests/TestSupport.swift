import Foundation
@testable import SwiftTLA

extension CompiledLayout {
    func testVariableID(named name: String) -> VariableID? {
        variables.first { $0.declaration.name == name }?.id
    }

    func testActionID(named name: String) -> ActionID? {
        actions.first { $0.declaration.name == name }?.id
    }
}

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

#if os(macOS)
private final class ExternalConsumerBundleAnchor: NSObject {}
#endif

func runExternalGeneratedConsumer(_ source: String) throws -> (status: Int32, output: String) {
    try withSerializedExternalPackageBuild {
        let fm = FileManager.default
        #if os(macOS)
        let products = Bundle(for: ExternalConsumerBundleAnchor.self).bundleURL.deletingLastPathComponent()
        #else
        let products = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        #endif
        let classicModules = products.appendingPathComponent("Modules")
        let modules = fm.fileExists(atPath: classicModules.path) ? classicModules : products
        let names = ["SwiftTLAMacros", "SwiftTLA"]
        let archives = names.map { products.appendingPathComponent("lib\($0).a") }
        let linkInputs: [URL]
        if archives.allSatisfy({ fm.fileExists(atPath: $0.path) }) {
            linkInputs = archives
        } else {
            linkInputs = try names.flatMap { name in
                let map = products.appendingPathComponent("\(name).build/output-file-map.json")
                let outputs = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: map))
                let objects = Set(outputs.values.compactMap { $0["object"] }).sorted()
                guard !objects.isEmpty else { throw CocoaError(.fileNoSuchFile) }
                return objects.map { URL(fileURLWithPath: $0, relativeTo: products) }
            }
        }
        guard let plugin = ["SwiftTLAPlugin", "SwiftTLAPlugin-tool"].map({ products.appendingPathComponent($0) })
            .first(where: { fm.isExecutableFile(atPath: $0.path) }) else { throw CocoaError(.fileNoSuchFile) }
        let directory = (externalConsumerScratch ?? fm.temporaryDirectory)
            .appendingPathComponent("generated-consumer-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let input = directory.appendingPathComponent("GeneratedConsumer.swift")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("observer")
        var driver = [ProcessInfo.processInfo.environment["SWIFT_EXEC"] ?? "swiftc"]
        #if os(macOS)
        #if arch(arm64)
        driver += ["-target", "arm64-apple-macos14.0"]
        #else
        driver += ["-target", "x86_64-apple-macos14.0"]
        #endif
        #endif
        let build = try runExternalConsumerProcess(driver + [
            "-parse-as-library", "-swift-version", "5",
            "-warnings-as-errors", "-enable-experimental-feature", "StrictConcurrency",
            "-package-name", "swifttla", "-module-name", "GeneratedConsumer", "-I", modules.path,
            "-load-plugin-executable", plugin.path + "#SwiftTLAPlugin", "-o", executable.path, input.path,
        ] + linkInputs.map(\.path))
        guard build.status == 0 else { return build }
        return try runExternalConsumerProcess([executable.path])
    }
}

private var externalConsumerScratch: URL? {
    ProcessInfo.processInfo.environment["SWIFTTLA_VALIDATION_SCRATCH_PATH"].map { URL(fileURLWithPath: $0) }
}

private let externalConsumerPackage = packageRoot()
    .appendingPathComponent("Tests/Fixtures/ExternalConsumerContracts")

private func executeExternalConsumer(
    _ arguments: [String]
) throws -> (status: Int32, output: String) {
    try withSerializedExternalPackageBuild {
        var arguments = arguments
        if let scratch = externalConsumerScratch {
            // Nested package builds share the wrapper's isolation and cleanup.
            arguments.insert(contentsOf: ["--scratch-path", scratch.appendingPathComponent("external-consumer").path], at: 1)
        }
        return try runExternalConsumerProcess(["swift"] + arguments)
    }
}

private func runExternalConsumerProcess(_ command: [String]) throws -> (status: Int32, output: String) {
    let output = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: outputData, encoding: .utf8) ?? "")
}

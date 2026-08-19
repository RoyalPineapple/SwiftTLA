import Foundation

func packageRoot() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
        directory.deleteLastPathComponent()
    }
    return directory
}

func throwingPackageRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
        let parent = directory.deletingLastPathComponent()
        guard parent != directory else { throw CocoaError(.fileNoSuchFile) }
        directory = parent
    }
    return directory
}

func projectURL(_ path: String) -> URL {
    packageRoot().appendingPathComponent(path).standardizedFileURL
}

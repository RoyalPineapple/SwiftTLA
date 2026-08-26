import Foundation

package enum RetainedEvidence {
  package static func projectRoot(_ url: URL) throws -> URL {
    let root = url.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw EvidenceFormatError.invalidField(record: url.path, field: "project root")
    }
    return root
  }

  package static func resolve(_ url: URL, beneath root: URL) throws -> URL {
    let candidate = url.path.hasPrefix("/") ? url : root.appendingPathComponent(url.path)
    var existing = candidate
    var suffix = [String]()
    while !FileManager.default.fileExists(atPath: existing.path) {
      let parent = existing.deletingLastPathComponent()
      guard parent != existing else { break }
      suffix.append(existing.lastPathComponent)
      existing = parent
    }
    let resolved = suffix.reversed().reduce(existing.resolvingSymlinksInPath().standardizedFileURL) {
      $0.appendingPathComponent($1)
    }.standardizedFileURL
    guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
      let field = url.path.hasPrefix("/") ? "path outside project root" : "path escape"
      throw EvidenceFormatError.invalidField(record: url.path, field: field)
    }
    return resolved
  }

  package static func relativePath(for url: URL, beneath root: URL) throws -> String {
    let resolved = try resolve(url, beneath: root)
    let prefix = root.path + "/"
    guard resolved.path.hasPrefix(prefix) else {
      throw EvidenceFormatError.invalidField(record: resolved.path, field: "project-relative evidence")
    }
    return String(resolved.path.dropFirst(prefix.count))
  }

  @discardableResult
  static func outputDirectory(_ url: URL, beneath root: URL) throws -> URL {
    let directory = try resolve(url, beneath: root)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw EvidenceFormatError.invalidField(record: directory.path, field: "output already exists")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @discardableResult
  static func createDirectory(_ url: URL, beneath root: URL) throws -> URL {
    let directory = try resolve(url, beneath: root)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func write(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
  }

  static func writeText(_ text: String, to url: URL) throws {
    try write(Data(text.utf8), to: url)
  }

  static func copy(_ source: URL, to destination: URL) throws {
    try FileManager.default.copyItem(at: source, to: destination)
  }

  static func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try write(data, to: url)
  }

  package static func reference(for url: URL, beneath root: URL, data: Data? = nil) throws -> RetainedFileReference {
    let url = try resolve(url, beneath: root)
    let bytes: Data
    if let data {
      bytes = data
    } else {
      bytes = try Data(contentsOf: url)
    }
    return try RetainedFileReference(
      path: relativePath(for: url, beneath: root),
      sha256: SHA256.hex(bytes))
  }

  package static func reference(for url: URL, beneath root: URL, pathPrefix: String) throws -> RetainedFileReference {
    let reference = try reference(for: url, beneath: root)
    return try RetainedFileReference(path: "\(pathPrefix)/\(reference.path)", sha256: reference.sha256)
  }

  private static func canonicalData<T: Encodable>(_ value: T, trailingNewline: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    if trailingNewline { data.append(0x0A) }
    return data
  }

  static func writeCanonical<T: Encodable>(_ value: T, to url: URL, trailingNewline: Bool = false) throws {
    try write(canonicalData(value, trailingNewline: trailingNewline), to: url)
  }

  package static func writePrettyCanonical<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try write(data, to: url)
  }
}

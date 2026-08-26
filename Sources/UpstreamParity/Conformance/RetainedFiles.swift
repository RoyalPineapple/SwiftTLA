import Foundation

package enum RetainedFiles {
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

  static func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try write(data, to: url)
  }

  static func writeCanonical<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try write(encoder.encode(value), to: url)
  }

}

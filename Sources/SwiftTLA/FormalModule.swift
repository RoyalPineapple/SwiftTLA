import Foundation

/// One source file in a TLA+ module bundle.
///
/// A formal module is a real source dependency, not text copied into a
/// consumer. The root file has a TLC configuration; imported files do not.
public struct TLAModuleFile: Sendable, Equatable {
  public let name: String
  public let tla: String
  public let cfg: String?

  public init(name: String, tla: String, cfg: String? = nil) {
    self.name = name
    self.tla = tla
    self.cfg = cfg
  }
}

/// The complete source input required to run TLC for one SwiftTLA model.
public struct TLAModuleBundle: Sendable, Equatable {
  public let root: TLAModuleFile
  public let imports: [TLAModuleFile]

  public init(root: TLAModuleFile, imports: [TLAModuleFile] = []) {
    self.root = root
    self.imports = imports
  }

  public var tla: String { root.tla }
  public var cfg: String { root.cfg ?? "" }
  public var files: [TLAModuleFile] { imports + [root] }

  /// Writes every module source file and the root TLC configuration into one
  /// directory. TLC resolves imports from this directory exactly as it would
  /// for an upstream multi-module specification.
  public func write(to directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true
    )
    for file in files {
      try file.tla.write(
        to: directory.appendingPathComponent("\(file.name).tla"),
        atomically: true,
        encoding: .utf8
      )
      if let cfg = file.cfg {
        try cfg.write(
          to: directory.appendingPathComponent("\(file.name).cfg"),
          atomically: true,
          encoding: .utf8
        )
      }
    }
  }
}

/// Imports a named TLA+ module as a source dependency.
///
/// Unlike `Use(spec:)`, this does not merge declarations into the consumer.
/// The exporter writes the module separately and the consumer emits an
/// `EXTENDS` relationship, matching TLA+ module semantics.
public struct ImportDecl: SpecComponent {
  public let module: TLASpec
  init(_ module: TLASpec) { self.module = module }
}

// swiftlint:disable:next identifier_name
public func Import(_ module: TLASpec) -> ImportDecl { ImportDecl(module) }

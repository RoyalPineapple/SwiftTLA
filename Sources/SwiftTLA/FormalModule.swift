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
public struct FormalModuleReplacement: Sendable, Equatable {
  /// The imported module operator to replace in a TLC configuration.
  public let operatorName: String
  /// The consumer-module definition that supplies the replacement value.
  public let definitionName: String
  /// The finite formal expression used by both SwiftTLA and TLC.
  public let expression: StateExpr

  public init(operatorName: String, definitionName: String, expression: StateExpr) {
    self.operatorName = operatorName
    self.definitionName = definitionName
    self.expression = expression
  }
}

/// Typed TLC configuration for one imported formal module.
///
/// The module remains a separate `.tla` source file. Its replacement values
/// live in the consumer module and are connected with scoped `.cfg` bindings.
public struct FormalModuleConfiguration: Sendable, Equatable {
  public let moduleName: String
  public let replacements: [FormalModuleReplacement]

  public init(moduleName: String, replacements: [FormalModuleReplacement]) {
    self.moduleName = moduleName
    self.replacements = replacements
  }
}

public struct ImportDecl: SpecComponent {
  public let module: TLASpec
  public let configuration: FormalModuleConfiguration?

  init(_ module: TLASpec, configuring configuration: FormalModuleConfiguration? = nil) {
    precondition(
      configuration == nil || configuration?.moduleName == module.name,
      "Formal module configuration must name the imported module."
    )
    self.module = module
    self.configuration = configuration
  }
}

// swiftlint:disable:next identifier_name
public func Import(_ module: TLASpec) -> ImportDecl { ImportDecl(module) }

// swiftlint:disable:next identifier_name
public func Import(
  _ module: TLASpec,
  configuring configuration: FormalModuleConfiguration
) -> ImportDecl {
  ImportDecl(module, configuring: configuration)
}

/// The formal modules that macro expansion can resolve from an authored
/// `Import(Module.module)` declaration.
public enum FormalModuleRegistry {
  public static func lookup(_ name: String) -> TLASpec? {
    switch name {
    case "ZSequences": ZSequences.module
    default: nil
    }
  }
}

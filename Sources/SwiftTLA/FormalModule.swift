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

/// A source-level linking failure in a TLA+ module bundle.
///
/// Linking deliberately happens before a renderer hands the bundle to TLC or
/// PlusCal. A missing module is a bundle construction error, not a tool error.
public enum TLAModuleBundleLinkError: Error, Equatable, Sendable, CustomStringConvertible {
  case duplicateModule(String)
  case missingModule(module: String, importedBy: String, line: Int)

  public var description: String {
    switch self {
    case .duplicateModule(let name):
      "The module bundle contains more than one \(name).tla source file."
    case .missingModule(let module, let importedBy, let line):
      "\(importedBy).tla line \(line) requires \(module).tla, but the bundle does not contain it."
    }
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

  /// Checks the complete in-memory module closure before it is written or
  /// passed to a formal tool. TLC's bundled standard modules are excluded;
  /// every other `EXTENDS` or `INSTANCE` target must be present in `imports`.
  public func validateLink(
    standardModules: Set<String>? = nil
  ) throws {
    let standardModules = standardModules ?? Self.tlcStandardModules
    var sources: [String: TLAModuleFile] = [:]
    for file in files {
      guard sources[file.name] == nil else {
        throw TLAModuleBundleLinkError.duplicateModule(file.name)
      }
      sources[file.name] = file
    }

    for file in files {
      for dependency in Self.dependencies(in: file.tla) where !standardModules.contains(dependency.name) {
        guard sources[dependency.name] != nil else {
          throw TLAModuleBundleLinkError.missingModule(
            module: dependency.name,
            importedBy: file.name,
            line: dependency.line
          )
        }
      }
    }
  }

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

  private struct Dependency {
    let name: String
    let line: Int
  }

  private static func dependencies(in source: String) -> [Dependency] {
    source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().flatMap { offset, rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("EXTENDS ") {
        return line.dropFirst("EXTENDS ".count).split(separator: ",").compactMap { token in
          let name = token.trimmingCharacters(in: .whitespaces)
          return isModuleIdentifier(name) ? Dependency(name: name, line: offset + 1) : nil
        }
      }
      guard let range = line.range(of: "INSTANCE ") else { return [] }
      let name = line[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
      guard isModuleIdentifier(name) else { return [] }
      return [Dependency(name: name, line: offset + 1)]
    }
  }

  private static func isModuleIdentifier(_ value: some StringProtocol) -> Bool {
    !value.isEmpty && value.first?.isLetter == true
  }

  private static let tlcStandardModules: Set<String> = [
    "Bags", "FiniteSets", "Integers", "Naturals", "Randomization", "RealTime", "Sequences", "TLC"
  ]
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

/// An actual expression supplied to a parameter of a named module instance.
public struct ModuleArgument: Sendable, Equatable {
  public let parameter: String
  public let value: StateExpr

  public init(_ parameter: String, value: some StateExprConvertible) {
    precondition(!parameter.isEmpty, "A module argument needs a parameter name.")
    self.parameter = parameter
    self.value = value.stateExpr
  }

  /// Builds an argument from a parsed formal expression.
  ///
  /// This is primarily used by the macro parser. Public callers normally use
  /// `value:` so Swift supplies the expression conversion.
  public init(_ parameter: String, expression: StateExpr) {
    precondition(!parameter.isEmpty, "A module argument needs a parameter name.")
    self.parameter = parameter
    self.value = expression
  }
}

/// A named TLA+ module instance.
///
/// `Instance("CC", of: ClientCentric.module)` exports as
/// `CC == INSTANCE ClientCentric`.  This is deliberately separate from
/// `Import`: an import is an `EXTENDS` relationship, while an instance keeps
/// the imported operators behind an explicit namespace such as `CC!Check`.
public struct FormalModuleInstance: SpecComponent, Sendable, Equatable {
  public let name: String
  public let module: TLASpec
  public let arguments: [ModuleArgument]

  public init(_ name: String, of module: TLASpec, with arguments: [ModuleArgument] = []) {
    precondition(!name.isEmpty, "A formal module instance needs a name.")
    let declared = Set(module.formalParameters.map(\.name))
    precondition(
      Set(arguments.map(\.parameter)).count == arguments.count,
      "A formal module instance cannot bind the same parameter twice."
    )
    precondition(
      Set(arguments.map(\.parameter)).isSubset(of: declared),
      "A formal module instance can bind only parameters declared by its module."
    )
    self.name = name
    self.module = module
    self.arguments = arguments
  }

  public static func == (lhs: FormalModuleInstance, rhs: FormalModuleInstance) -> Bool {
    lhs.name == rhs.name && lhs.module.name == rhs.module.name && lhs.arguments == rhs.arguments
  }

  /// References one operator through this instance's TLA+ namespace.
  ///
  /// The expression exports as `Name!Operator(...)` and the checker resolves
  /// it against this instance's separately declared module.
  public func call(_ operatorName: String, _ arguments: StateExpr...) -> StateExpr {
    .recursiveCall("\(name)!\(operatorName)", arguments)
  }
}

/// Applies a formal value operator by its TLA+ name while retaining its result type.
///
/// This is the typed boundary for imported community-module definitions.  It is
/// deliberately not a Swift closure: the operator name and every argument remain
/// in `StateExpr` for parser fidelity, evaluation, and TLA+ emission.
public func FormalCall<Result: TLAValueType>(
  _ name: String
) -> Expr<Result> {
  Expr(.operatorApplication(.reference(name, arity: 0), []))
}

/// Applies a nullary formal operator with an explicit result-type witness.
///
/// This form is for a formal value nested in an otherwise uncontextualized
/// expression, such as an imported predicate argument.
public func FormalCall<Result: TLAValueType>(
  as _: Result.Type,
  _ name: String
) -> Expr<Result> {
  FormalCall(name)
}

public func FormalCall<Result: TLAValueType, Value: StateExprConvertible>(
  _ name: String,
  _ value: Value
) -> Expr<Result> {
  Expr(.operatorApplication(.reference(name, arity: 1), [.value(value.stateExpr)]))
}

public func FormalCall<
  Result: TLAValueType,
  First: StateExprConvertible,
  Second: StateExprConvertible
>(
  _ name: String,
  _ first: First,
  _ second: Second
) -> Expr<Result> {
  Expr(.operatorApplication(.reference(name, arity: 2), [
    .value(first.stateExpr), .value(second.stateExpr)
  ]))
}

/// Applies a binary formal operator with an explicit result-type witness.
public func FormalCall<
  Result: TLAValueType,
  First: StateExprConvertible,
  Second: StateExprConvertible
>(
  as _: Result.Type,
  _ name: String,
  _ first: First,
  _ second: Second
) -> Expr<Result> {
  FormalCall(name, first, second)
}

/// Applies an executable formal operator exported by a named `INSTANCE`.
///
/// Module instances are an explicit source-level namespace in TLA+.  Keeping
/// the namespace here avoids treating an imported definition as a host closure
/// or leaking raw `StateExpr` construction into an application model.
public func ModuleCall<Result: TLAValueType>(
  _ instance: String,
  _ operatorName: String
) -> Expr<Result> {
  FormalCall("\(instance)!\(operatorName)")
}

public func ModuleCall<Result: TLAValueType, Value: StateExprConvertible>(
  _ instance: String,
  _ operatorName: String,
  _ value: Value
) -> Expr<Result> {
  FormalCall("\(instance)!\(operatorName)", value)
}

public func ModuleCall<
  Result: TLAValueType,
  First: StateExprConvertible,
  Second: StateExprConvertible
>(
  _ instance: String,
  _ operatorName: String,
  _ first: First,
  _ second: Second
) -> Expr<Result> {
  FormalCall("\(instance)!\(operatorName)", first, second)
}

/// Applies a binary imported operator with an explicit result-type witness.
///
/// The witness is compile-time only; the emitted formal operator remains the
/// same namespaced TLA+ application.
public func ModuleCall<
  Result: TLAValueType,
  First: StateExprConvertible,
  Second: StateExprConvertible
>(
  as _: Result.Type,
  _ instance: String,
  _ operatorName: String,
  _ first: First,
  _ second: Second
) -> Expr<Result> {
  ModuleCall(instance, operatorName, first, second)
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

// swiftlint:disable identifier_name
/// Adds a named, source-level TLA+ `INSTANCE` declaration.
public func Instance(
  _ name: String,
  of module: TLASpec,
  with arguments: [ModuleArgument] = []
) -> FormalModuleInstance {
  FormalModuleInstance(name, of: module, with: arguments)
}
// swiftlint:enable identifier_name

/// The formal modules that macro expansion can resolve from authored
/// `Import(Module.module)` and `Instance("name", of: Module.module)` declarations.
public enum FormalModuleRegistry {
  public static func lookup(_ name: String) -> TLASpec? {
    switch name {
    case "Folds": Folds.module
    case "Functions", "FunctionsModule": FunctionsModule.module
    case "Util", "KeyValueStoreUtil": KeyValueStoreUtil.module
    case "ClientCentric": ClientCentric.module
    case "Consensus", "ByzPaxosConsensus": ByzPaxosConsensus.module
    case "ZSequences": ZSequences.module
    default: nil
    }
  }
}

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
  case cyclicModule(module: String, path: [String])

  public var description: String {
    switch self {
    case .duplicateModule(let name):
      return "The module bundle contains more than one \(name).tla source file."
    case .missingModule(let module, let importedBy, let line):
      return "\(importedBy).tla line \(line) requires \(module).tla, but the bundle does not contain it."
    case .cyclicModule(let module, let path):
      return "The module bundle has a cycle through \(module): \(path.joined(separator: " -> "))."
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

    var visited: Set<String> = []
    var active: [String] = []
    func visit(_ name: String) throws {
      if let cycleStart = active.firstIndex(of: name) {
        throw TLAModuleBundleLinkError.cyclicModule(
          module: name,
          path: Array(active[cycleStart...]) + [name]
        )
      }
      guard visited.insert(name).inserted else { return }
      active.append(name)
      defer { active.removeLast() }
      guard let file = sources[name] else { return }
      for dependency in Self.dependencies(in: file.tla) where !standardModules.contains(dependency.name) {
        try visit(dependency.name)
      }
    }

    try visit(root.name)
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
    var dependencies: [Dependency] = []
    for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("EXTENDS ") {
        for token in line.dropFirst("EXTENDS ".count).split(separator: ",") {
          let name = token.trimmingCharacters(in: .whitespaces)
          if isModuleIdentifier(name) {
            dependencies.append(Dependency(name: name, line: offset + 1))
          }
        }
        continue
      }
      guard let range = line.range(of: "INSTANCE ") else { continue }
      let name = line[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
      if isModuleIdentifier(name) {
        dependencies.append(Dependency(name: String(name), line: offset + 1))
      }
    }
    return dependencies
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

/// A validated, source-owned formal module graph for one compiled root.
///
/// Entries are dependency-first and include the root exactly once. Every
/// retained edge records its declared relationship instead of flattening
/// imports and named instances into a name-only module list.
public struct FormalModuleClosure: Sendable {
  public struct Entry: Sendable {
    public let module: TLASpec
    public let owningRoot: String
    public let structuralPath: [String]
  }

  public enum EdgeKind: Sendable, Equatable {
    case importModule(configuration: FormalModuleConfiguration?)
    case namedInstance(namespace: String, arguments: [ModuleArgument])
  }

  public struct Edge: Sendable, Equatable {
    public let owningRoot: String
    public let fromModule: String
    public let toModule: String
    public let structuralPath: [String]
    public let kind: EdgeKind
  }

  public let root: Entry
  public let entries: [Entry]
  public let edges: [Edge]

  public static func resolve(root: TLASpec) throws -> FormalModuleClosure {
    var entries: [Entry] = []
    var edges: [Edge] = []
    var sourceByName: [String: String] = [:]
    var active: [String] = []

    func diagnostic(
      _ code: CompilationDiagnostic.Code,
      path: [String],
      expected: String,
      actual: String,
      nextSafeAction: String
    ) -> CompilationDiagnostic {
      CompilationDiagnostic(
        code: code,
        stage: .linking,
        path: path.joined(separator: "."),
        expected: expected,
        actual: actual,
        nextSafeAction: nextSafeAction
      )
    }

    func validateDeclaredRelationships(_ module: TLASpec, path: [String]) throws {
      let importNames = module.imports.map(\.name)
      if let duplicate = Self.firstDuplicate(in: importNames) {
        throw diagnostic(
          .duplicateFormalModuleImport,
          path: path + ["imports", duplicate],
          expected: "one import relationship for '\(duplicate)'",
          actual: "multiple import relationships",
          nextSafeAction: "Keep one import relationship for the module, then compile again."
        )
      }

      let configurationNames = module.importConfigurations.map(\.moduleName)
      if let duplicate = Self.firstDuplicate(in: configurationNames) {
        throw diagnostic(
          .duplicateFormalModuleConfiguration,
          path: path + ["configurations", duplicate],
          expected: "one configuration for imported module '\(duplicate)'",
          actual: "multiple configurations",
          nextSafeAction: "Merge the replacement bindings into one configuration, then compile again."
        )
      }
      for configuration in module.importConfigurations {
        guard importNames.contains(configuration.moduleName) else {
          throw diagnostic(
            .missingFormalModuleConfigurationTarget,
            path: path + ["configurations", configuration.moduleName],
            expected: "a declared import named '\(configuration.moduleName)'",
            actual: "no matching import",
            nextSafeAction: "Import the configured module or remove the configuration, then compile again."
          )
        }
        if let duplicate = Self.firstDuplicate(in: configuration.replacements.map(\.operatorName)) {
          throw diagnostic(
            .duplicateFormalModuleReplacement,
            path: path + ["configurations", configuration.moduleName, duplicate],
            expected: "one replacement binding for '\(duplicate)'",
            actual: "multiple replacement bindings",
            nextSafeAction: "Keep one replacement binding for the operator, then compile again."
          )
        }
      }

      if let instance = module.moduleInstances.first(where: {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        throw diagnostic(
          .invalidFormalModuleInstanceNamespace,
          path: path + ["instances"],
          expected: "a non-empty instance namespace",
          actual: "an empty namespace for module '\(instance.module.name)'",
          nextSafeAction: "Give the instance a namespace, then compile again."
        )
      }
      if let duplicate = Self.firstDuplicate(in: module.moduleInstances.map(\.name)) {
        throw diagnostic(
          .duplicateFormalModuleInstanceNamespace,
          path: path + ["instances", duplicate],
          expected: "one named instance namespace '\(duplicate)'",
          actual: "multiple instances share that namespace",
          nextSafeAction: "Rename or remove the duplicate instance, then compile again."
        )
      }
      for instance in module.moduleInstances {
        let arguments = instance.arguments.map(\.parameter)
        if let duplicate = Self.firstDuplicate(in: arguments) {
          throw diagnostic(
            .duplicateFormalModuleArgument,
            path: path + ["instances", instance.name, duplicate],
            expected: "one binding for parameter '\(duplicate)'",
            actual: "multiple bindings",
            nextSafeAction: "Keep one argument for the parameter, then compile again."
          )
        }
        let declared = Set(instance.module.formalParameters.map(\.name))
        if let invalid = arguments.first(where: { $0.isEmpty || !declared.contains($0) }) {
          throw diagnostic(
            .invalidFormalModuleArgument,
            path: path + ["instances", instance.name, invalid],
            expected: "a declared non-empty parameter of '\(instance.module.name)'",
            actual: invalid.isEmpty ? "an empty parameter name" : "an undeclared parameter",
            nextSafeAction: "Bind only declared module parameters, then compile again."
          )
        }
      }
    }

    func visit(_ module: TLASpec, path: [String]) throws {
      try validateDeclaredRelationships(module, path: path)
      let source = module.compilationFingerprint
      if let previousSource = sourceByName[module.name] {
        guard previousSource == source else {
          throw diagnostic(
            .conflictingFormalModuleSource,
            path: path,
            expected: "one canonical source for module '\(module.name)'",
            actual: "a second source with the same module name",
            nextSafeAction: "Rename one module or import the same canonical source, then compile again."
          )
        }
        if let cycleStart = active.firstIndex(of: module.name) {
          throw diagnostic(
            .cyclicFormalModule,
            path: path,
            expected: "an acyclic formal module graph",
            actual: Array(active[cycleStart...]).joined(separator: " -> ") + " -> \(module.name)",
            nextSafeAction: "Break the import or instance cycle, then compile again."
          )
        }
        return
      }

      sourceByName[module.name] = source
      active.append(module.name)
      defer { active.removeLast() }

      for imported in module.imports {
        let configuration = module.importConfigurations.first { $0.moduleName == imported.name }
        let edgePath = path + [imported.name]
        edges.append(Edge(
          owningRoot: root.name,
          fromModule: module.name,
          toModule: imported.name,
          structuralPath: edgePath,
          kind: .importModule(configuration: configuration)
        ))
        try visit(imported, path: edgePath)
      }
      for instance in module.moduleInstances {
        let edgePath = path + [instance.name, instance.module.name]
        edges.append(Edge(
          owningRoot: root.name,
          fromModule: module.name,
          toModule: instance.module.name,
          structuralPath: edgePath,
          kind: .namedInstance(namespace: instance.name, arguments: instance.arguments)
        ))
        try visit(instance.module, path: edgePath)
      }

      entries.append(Entry(module: module, owningRoot: root.name, structuralPath: path))
    }

    try visit(root, path: [root.name])
    try Self.validateImportedSymbols(entries: entries, edges: edges, diagnostic: diagnostic)
    guard let rootEntry = entries.last else {
      fatalError("Formal module closure resolution produced no root entry.")
    }
    return FormalModuleClosure(root: rootEntry, entries: entries, edges: edges)
  }

  private static func firstDuplicate(in names: [String]) -> String? {
    var seen: Set<String> = []
    return names.first { !seen.insert($0).inserted }
  }

  private static func validateImportedSymbols(
    entries: [Entry],
    edges: [Edge],
    diagnostic: (
      CompilationDiagnostic.Code, [String], String, String, String
    ) -> CompilationDiagnostic
  ) throws {
    let importsByModule = Dictionary(grouping: edges) { $0.fromModule }
    var exportedSymbols: [String: Set<String>] = [:]

    for entry in entries {
      var symbols = Set(entry.module.recursiveFuncs.map(\.name))
      symbols.formUnion(entry.module.formalOperatorDefinitions.map(\.name))
      for edge in importsByModule[entry.module.name, default: []] {
        guard case .importModule = edge.kind else { continue }
        guard let imported = exportedSymbols[edge.toModule] else { continue }
        if let duplicate = imported.first(where: { symbols.contains($0) }) {
          throw diagnostic(
            .duplicateFormalModuleSymbol,
            edge.structuralPath,
            "one visible imported symbol named '\(duplicate)'",
            "multiple imports expose that symbol",
            "Qualify one relationship with an instance or remove the ambiguous import, then compile again."
          )
        }
        symbols.formUnion(imported)
      }
      exportedSymbols[entry.module.name] = symbols
    }
  }
}

/// An actual expression supplied to a parameter of a named module instance.
public struct ModuleArgument: Sendable, Equatable {
  public let parameter: String
  public let value: StateExpr

  public init(_ parameter: String, value: some StateExprConvertible) {
    self.parameter = parameter
    self.value = value.stateExpr
  }

  /// Builds an argument from a parsed formal expression.
  ///
  /// This is primarily used by the macro parser. Public callers normally use
  /// `value:` so Swift supplies the expression conversion.
  public init(_ parameter: String, expression: StateExpr) {
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

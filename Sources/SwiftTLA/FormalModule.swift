import Foundation

/// One source file in a TLA+ module bundle.
///
/// A formal module is a real source dependency, not text copied into a
/// consumer. The root file has a TLC configuration; imported files do not.
public struct TLAModuleFile: Sendable, Equatable {
  public let name: String
  public let tla: String
  public let cfg: String?

  package init(name: String, tla: String, cfg: String? = nil) {
    self.name = name
    self.tla = tla
    self.cfg = cfg
  }
}

/// A post-render integrity failure in a TLA+ module bundle.
///
/// The compiler's `FormalModuleClosure` is the semantic linker. This type only
/// reports that emitted text files no longer form the already-linked closure
/// that TLC will receive.
public enum TLAModuleBundleIntegrityError: Error, Equatable, Sendable, CustomStringConvertible {
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
  /// One linked module's provenance in a compiler-produced bundle.
  public struct OwnershipEntry: Sendable, Equatable, Codable {
    public let moduleName: String
    public let owningRoot: String
    public let structuralPath: [String]

    public init(moduleName: String, owningRoot: String, structuralPath: [String]) {
      self.moduleName = moduleName
      self.owningRoot = owningRoot
      self.structuralPath = structuralPath
    }
  }

  /// One source-level module relationship retained by compilation.
  public struct ModuleDependency: Sendable, Equatable, Codable {
    public let importingModule: String
    public let importedModule: String
    public let structuralPath: [String]

    public init(
      importingModule: String,
      importedModule: String,
      structuralPath: [String]
    ) {
      self.importingModule = importingModule
      self.importedModule = importedModule
      self.structuralPath = structuralPath
    }
  }

  /// Provenance identifies compiler-linked output and external formal-source input.
  public enum Provenance: Sendable, Equatable {
    case compiled(
      identity: CompilationIdentity,
      ownership: [OwnershipEntry],
      dependencies: [ModuleDependency]
    )
    case external
  }

  public let root: TLAModuleFile
  public let imports: [TLAModuleFile]
  public let provenance: Provenance

  init(
    root: TLAModuleFile,
    imports: [TLAModuleFile] = [],
    provenance: Provenance = .external
  ) {
    self.root = root
    self.imports = imports
    self.provenance = provenance
  }

  /// Creates a bundle supplied by an external formal-source boundary.
  package static func external(
    root: TLAModuleFile,
    imports: [TLAModuleFile] = []
  ) -> Self {
    Self(root: root, imports: imports, provenance: .external)
  }

  public var tla: String { root.tla }
  public var cfg: String { root.cfg ?? "" }
  public var files: [TLAModuleFile] { imports + [root] }

  /// Checks that compiler-rendered files materialize their declared closure.
  public func validateDeclaredClosure() throws {
    var sources: [String: TLAModuleFile] = [:]
    for file in files {
      guard sources[file.name] == nil else {
        throw TLAModuleBundleIntegrityError.duplicateModule(file.name)
      }
      sources[file.name] = file
    }

    guard case let .compiled(_, ownership, dependencies) = provenance else {
      return
    }

    let expectedModules = Set(ownership.map(\.moduleName))
    guard expectedModules == Set(sources.keys),
          ownership.contains(where: { $0.moduleName == root.name }) else {
      throw TLAModuleBundleIntegrityError.missingModule(
        module: root.name,
        importedBy: root.name,
        line: 0
      )
    }

    for dependency in dependencies {
      guard sources[dependency.importingModule] != nil,
            sources[dependency.importedModule] != nil else {
        throw TLAModuleBundleIntegrityError.missingModule(
          module: dependency.importedModule,
          importedBy: dependency.importingModule,
          line: 0
        )
      }
    }

    var visited: Set<String> = []
    var active: [String] = []
    func visit(_ name: String) throws {
      if let cycleStart = active.firstIndex(of: name) {
        throw TLAModuleBundleIntegrityError.cyclicModule(
          module: name,
          path: Array(active[cycleStart...]) + [name]
        )
      }
      guard visited.insert(name).inserted else { return }
      active.append(name)
      defer { active.removeLast() }
      for dependency in dependencies where dependency.importingModule == name {
        try visit(dependency.importedModule)
      }
    }

    try visit(root.name)
  }
}

/// Imports a named TLA+ module as a source dependency.
///
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
package struct FormalModuleClosure: Sendable {
  struct ModuleID: Hashable, Sendable {
    let ordinal: Int
  }

  struct ModulePlanContext: Sendable {
    let closure: FormalModuleClosure
    let incomingModuleParameters: [FormalModuleReplacement]
  }

  struct LinkedOperatorPlan: Sendable {
    let recursiveFunctions: [RecursiveFunc]
    let formalOperatorDefinitions: [FormalOperatorDefinition]
  }

  struct Entry: Sendable {
    let id: ModuleID
    let module: TLASpec
    let owningRoot: String
    let structuralPath: [String]
  }

  enum EdgeKind: Sendable, Equatable {
    case importModule(configuration: FormalModuleConfiguration?)
    case namedInstance(namespace: String, arguments: [ModuleArgument])
  }

  struct Edge: Sendable, Equatable {
    let owningRoot: String
    let fromModule: String
    let toModule: String
    let structuralPath: [String]
    let kind: EdgeKind
  }

  let root: Entry
  let entries: [Entry]
  let edges: [Edge]
  let linkedOperators: LinkedOperatorPlan

  func planContext(for entry: Entry) -> ModulePlanContext {
    var reachable = Set([entry.module.name])
    var pending = [entry.module.name]
    while let module = pending.popLast() {
      for edge in edges where edge.fromModule == module {
        if reachable.insert(edge.toModule).inserted {
          pending.append(edge.toModule)
        }
      }
    }
    let entries = entries.filter { reachable.contains($0.module.name) }
    let edges = edges.filter {
      reachable.contains($0.fromModule) && reachable.contains($0.toModule)
    }
    let incomingModuleParameters = self.edges.flatMap { edge -> [FormalModuleReplacement] in
      guard edge.toModule == entry.module.name,
            case .importModule(let configuration) = edge.kind else { return [] }
      return configuration?.replacements ?? []
    }
    return .init(
      closure: .init(
        root: entry,
        entries: entries,
        edges: edges,
        linkedOperators: Self.makeLinkedOperatorPlan(root: entry, entries: entries, edges: edges)
      ),
      incomingModuleParameters: incomingModuleParameters
    )
  }

  private static func makeLinkedOperatorPlan(
    root: Entry,
    entries: [Entry],
    edges: [Edge]
  ) -> LinkedOperatorPlan {
    let modules = Dictionary(uniqueKeysWithValues: entries.map { ($0.module.name, $0.module) })
    func recursiveFunctions(
      named name: String,
      replacements: [FormalModuleReplacement]
    ) -> [RecursiveFunc] {
      guard let module = modules[name] else { return [] }
      var result: [RecursiveFunc] = []
      for edge in edges where edge.fromModule == name {
        switch edge.kind {
        case .importModule(let configuration):
          result += recursiveFunctions(
            named: edge.toModule,
            replacements: configuration?.replacements ?? []
          )
        case .namedInstance(let namespace, let arguments):
          let functions = recursiveFunctions(named: edge.toModule, replacements: [])
          let localNames = Set(functions.map(\.name))
          result += functions.map { function in
            let body = arguments.reduce(function.body) {
              StateExpr.substituteVariable($1.parameter, with: $1.value, in: $0)
            }
            return RecursiveFunc(
              name: "\(namespace)!\(function.name)", params: function.params,
              body: StateExpr.renamingRecursiveCalls(in: body) {
                localNames.contains($0) ? "\(namespace)!\($0)" : $0
              }
            )
          }
        }
      }
      result += module.recursiveFuncs.map { function in
        RecursiveFunc(
          name: function.name, params: function.params,
          body: replacements.reduce(function.body) {
            StateExpr.substituteVariable($1.operatorName, with: $1.expression, in: $0)
          }
        )
      }
      return result
    }

    func formalOperatorDefinitions(
      _ name: String,
      replacements: [FormalModuleReplacement]
    ) -> [FormalOperatorDefinition] {
      guard let module = modules[name] else { return [] }
      var result: [FormalOperatorDefinition] = []
      for edge in edges where edge.fromModule == name {
        switch edge.kind {
        case .importModule(let configuration):
          result += formalOperatorDefinitions(
            edge.toModule,
            replacements: configuration?.replacements ?? []
          )
        case .namedInstance(let namespace, let arguments):
          let definitions = formalOperatorDefinitions(edge.toModule, replacements: [])
          let localNames = Set(definitions.map(\.name))
          result += definitions.map { definition in
            let body = arguments.reduce(definition.body) {
              StateExpr.substituteVariable($1.parameter, with: $1.value, in: $0)
            }
            return FormalOperatorDefinition(
              name: "\(namespace)!\(definition.name)", parameters: definition.parameters,
              body: StateExpr.renamingRecursiveCalls(in: body) {
                localNames.contains($0) ? "\(namespace)!\($0)" : $0
              }
            )
          }
        }
      }
      result += module.formalOperatorDefinitions.map { definition in
        FormalOperatorDefinition(
          name: definition.name,
          parameters: definition.parameters,
          body: replacements.reduce(definition.body) {
            StateExpr.substituteVariable($1.operatorName, with: $1.expression, in: $0)
          }
        )
      }
      return result
    }

    return .init(
      recursiveFunctions: recursiveFunctions(named: root.module.name, replacements: []),
      formalOperatorDefinitions: formalOperatorDefinitions(root.module.name, replacements: [])
    )
  }

  static func resolve(root: TLASpec) throws -> FormalModuleClosure {
    var entries: [Entry] = []
    var edges: [Edge] = []
    var sourceByName: [String: CompilationIdentity] = [:]
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
      let parameterNames = module.formalParameters.map(\.name)
      if parameterNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        throw diagnostic(.invalidFormalModuleParameter, path: path + ["parameters"], expected: "a non-empty formal parameter", actual: "an empty parameter name", nextSafeAction: "Name the formal parameter, then compile again.")
      }
      if let duplicate = Self.firstDuplicate(in: parameterNames) {
        throw diagnostic(.duplicateFormalModuleParameter, path: path + ["parameters", duplicate], expected: "one formal parameter named '\(duplicate)'", actual: "multiple formal parameters", nextSafeAction: "Rename or remove the duplicate parameter, then compile again.")
      }
      let importNames = module.imports.map(\.name)
      var sourceByImportName: [String: CompilationIdentity] = [:]
      for imported in module.imports {
        let source = imported.compilationIdentity
        if let firstSource = sourceByImportName[imported.name] {
          guard firstSource == source else {
            throw diagnostic(
              .conflictingFormalModuleSource,
              path: path + ["imports", imported.name],
              expected: "one canonical source for module '\(imported.name)'",
              actual: "multiple distinct canonical sources",
              nextSafeAction: "Rename one module or import the same canonical source, then compile again."
            )
          }
          throw diagnostic(
            .duplicateFormalModuleImport,
            path: path + ["imports", imported.name],
            expected: "one import relationship for '\(imported.name)'",
            actual: "multiple import relationships",
            nextSafeAction: "Keep one import relationship for the module, then compile again."
          )
        }
        sourceByImportName[imported.name] = source
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
        guard let target = module.imports.first(where: { $0.name == configuration.moduleName }) else { continue }
        let targetSymbols = Self.moduleInterfaceSymbols(of: target)
        for replacement in configuration.replacements where replacement.operatorName.isEmpty || !targetSymbols.contains(replacement.operatorName) {
          throw diagnostic(.unresolvedFormalModuleReplacement, path: path + ["configurations", configuration.moduleName, replacement.operatorName], expected: "a structural interface symbol of '\(target.name)'", actual: "an unresolved replacement name", nextSafeAction: "Configure a formal parameter or free module symbol, then compile again.")
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
        let arguments = module.instanceArguments(for: instance).map(\.parameter)
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
          .union(instance.module.variables.map(\.name))
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
      let source = module.compilationIdentity
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
          kind: .namedInstance(namespace: instance.name, arguments: module.instanceArguments(for: instance))
        ))
        try visit(instance.module, path: edgePath)
      }

      entries.append(
        Entry(
          id: .init(ordinal: entries.count),
          module: module,
          owningRoot: root.name,
          structuralPath: path
        )
      )
    }

    try visit(root, path: [root.name])
    try Self.validateImportedSymbols(entries: entries, edges: edges, diagnostic: diagnostic)
    guard let rootEntry = entries.last else {
      throw diagnostic(
        .emptyFormalModuleClosure,
        path: [root.name],
        expected: "the root module in the linked closure",
        actual: "an empty closure",
        nextSafeAction: "Compile the source model again."
      )
    }
    return FormalModuleClosure(
      root: rootEntry,
      entries: entries,
      edges: edges,
      linkedOperators: Self.makeLinkedOperatorPlan(root: rootEntry, entries: entries, edges: edges)
    )
  }

  private static func firstDuplicate(in names: [String]) -> String? {
    var seen: Set<String> = []
    return names.first { !seen.insert($0).inserted }
  }

  /// Names which a consumer may configure when it links this module.
  ///
  /// This intentionally uses the typed scope analysis instead of reflecting strings.
  /// A binder, local operator, assignment target, or record field is not an
  /// importable interface symbol merely because it happens to share a name
  /// with one.
  private static func moduleInterfaceSymbols(of module: TLASpec) -> Set<String> {
    var symbols = Set(module.formalParameters.map(\.name))
    var moduleDeclarations = Set(module.variables.map(\.name))
      .union(module.constants.map(\.name))
      .union(module.recursiveFuncs.map(\.name))
      .union(module.formalOperatorDefinitions.map(\.name))
    if !module.variables.isEmpty || !module.actions.isEmpty {
      moduleDeclarations.formUnion(["Init", "Next", "Spec"])
    }

    func actionFreeNames(_ action: ActionExpr) -> Set<String> {
      switch action {
      case .assign(_, let value), .guard_(let value), .chooseAction(_, let value):
        return value.freeVariableNames
      case .unchanged:
        return []
      case .existsAction(let name, let set, let body):
        return set.freeVariableNames.union(actionFreeNames(body).subtracting([name]))
      case .ifElse(let condition, let then, let otherwise):
        return condition.freeVariableNames
          .union(actionFreeNames(then))
          .union(actionFreeNames(otherwise))
      case .define(let name, let value, let body):
        return value.freeVariableNames.union(actionFreeNames(body).subtracting([name]))
      case .and(let lhs, let rhs), .or(let lhs, let rhs):
        return actionFreeNames(lhs).union(actionFreeNames(rhs))
      }
    }

    var freeNames = module.variables.flatMap {
      [$0.initialSet, $0.initExpr, $0.lazySet].compactMap { $0?.freeVariableNames }
    }.reduce(into: Set<String>()) { $0.formUnion($1) }
    for action in module.actions {
      freeNames.formUnion(actionFreeNames(action.body).subtracting(Set(action.bindings.map(\.name))))
    }
    module.invariants.forEach { freeNames.formUnion($0.body.freeVariableNames) }
    for temporal in module.temporalProperties {
      switch temporal.expr {
      case .always(let expression), .eventually(let expression), .alwaysEventually(let expression),
           .eventuallyAlways(let expression):
        freeNames.formUnion(expression.freeVariableNames)
      case .leadsTo(let source, let target):
        freeNames.formUnion(source.freeVariableNames)
        freeNames.formUnion(target.freeVariableNames)
      }
    }
    if let constraint = module.constraint { freeNames.formUnion(constraint.freeVariableNames) }
    if let assume = module.assume { freeNames.formUnion(assume.freeVariableNames) }
    for function in module.recursiveFuncs {
      freeNames.formUnion(function.body.freeVariableNames.subtracting(Set(function.params)))
    }
    for definition in module.formalOperatorDefinitions {
      freeNames.formUnion(definition.body.freeVariableNames.subtracting(Set(definition.parameters.map(\.name))))
    }
    symbols.formUnion(freeNames.subtracting(moduleDeclarations))
    return symbols
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
      let localSymbols = entry.module.recursiveFuncs.map(\.name) + entry.module.formalOperatorDefinitions.map(\.name)
      if let duplicate = Self.firstDuplicate(in: localSymbols) {
        throw diagnostic(.duplicateFormalModuleSymbol, entry.structuralPath + [duplicate], "one local symbol named '\(duplicate)'", "multiple local declarations", "Rename or remove the duplicate declaration, then compile again.")
      }
      for edge in importsByModule[entry.module.name, default: []] {
        if case .namedInstance(let namespace, _) = edge.kind, let imported = exportedSymbols[edge.toModule] {
          let instanceSymbols = imported.map { "\(namespace)!\($0)" }
          if let duplicate = instanceSymbols.first(where: { symbols.contains($0) }) {
            throw diagnostic(.duplicateFormalModuleSymbol, edge.structuralPath, "one visible symbol named '\(duplicate)'", "a local or imported symbol has the same qualified name", "Rename the instance or conflicting symbol, then compile again.")
          }
          symbols.formUnion(instanceSymbols)
          continue
        }
        guard case .importModule = edge.kind, let imported = exportedSymbols[edge.toModule] else { continue }
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
  public let plusCalPhase: AuthoredPlusCalDeclarationPhase
  public let plusCalDependencies: [String]

  public init(
    _ name: String,
    of module: TLASpec,
    with arguments: [ModuleArgument] = [],
    plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
    dependsOn: [String] = []
  ) {
    self.name = name
    self.module = module
    self.arguments = arguments
    self.plusCalPhase = plusCalPhase
    self.plusCalDependencies = dependsOn
  }

  public static func == (lhs: FormalModuleInstance, rhs: FormalModuleInstance) -> Bool {
    lhs.name == rhs.name && lhs.module.name == rhs.module.name && lhs.arguments == rhs.arguments
      && lhs.plusCalPhase == rhs.plusCalPhase && lhs.plusCalDependencies == rhs.plusCalDependencies
  }

  public var reference: FormalModuleInstanceReference {
    .init(instance: self)
  }

  /// References one operator through this instance's TLA+ namespace.
  ///
  /// The expression exports as `Name!Operator(...)` and the checker resolves
  /// it against this instance's separately declared module.
  public func call(_ operatorName: String, _ arguments: StateExpr...) -> StateExpr {
    .recursiveCall("\(name)!\(operatorName)", arguments)
  }
}

/// A source-model reference to one declared module instance.
public struct FormalModuleInstanceReference: Sendable, Equatable {
  let namespace: String

  init(instance: FormalModuleInstance) {
    self.namespace = instance.name
  }

  func resolves(_ instance: FormalModuleInstance) -> Bool {
    namespace == instance.name
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
  with arguments: [ModuleArgument] = [],
  plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
  dependsOn: [String] = []
) -> FormalModuleInstance {
  FormalModuleInstance(name, of: module, with: arguments, plusCalPhase: plusCalPhase, dependsOn: dependsOn)
}
// swiftlint:enable identifier_name

enum BuiltInFormalModules {
  static func resolve(_ sourceName: String) -> TLASpec? {
    switch sourceName {
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

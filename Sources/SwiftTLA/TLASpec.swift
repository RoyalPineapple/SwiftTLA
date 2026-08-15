public enum CollectionVarType: Sendable, Equatable {
  case scalar
  case set
  case array(Int)
  case dictionary(Int)
}
public struct NamedVar: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let initial: TLAValue
  public let initialSet: StateExpr?
  public let initExpr: StateExpr?
  public let lazySet: StateExpr?  // expression-backed nondeterministic init
  public let collectionType: CollectionVarType
  public init(
    name: String, initial: TLAValue, initialSet: StateExpr? = nil, initExpr: StateExpr? = nil,
    lazySet: StateExpr? = nil, collectionType: CollectionVarType = .scalar
  ) {
    self.name = name
    self.initial = initial
    self.initialSet = initialSet
    self.initExpr = initExpr
    self.lazySet = lazySet
    self.collectionType = collectionType
  }
  public var description: String {
    if let s = lazySet { return "\(name) \\in \(s)" }
    if let s = initialSet { return "\(name) \\in \(s)" }
    return "\(name) = \(initial)"
  }
}
public struct ActionBinding: Sendable, Hashable, Equatable {
  public let name: String
  public let values: [TLAValue]
  public init(name: String, values: [TLAValue]) {
    self.name = name
    self.values = values
  }
}
public protocol ActionParameterDescriptor: Sendable {
  var actionBinding: ActionBinding { get }
}
public struct ActionParameter<Domain: TLAValueType & Sendable>: Sendable {
  public let name: String
  public let values: [Domain]
  public init(_ name: String, values: [Domain]) {
    self.name = name
    self.values = values
  }
  public var actionBinding: ActionBinding {
    ActionBinding(name: name, values: values.map(\.tlaValue))
  }
}
extension ActionParameter: ActionParameterDescriptor {}
public struct TLAActionInvocation: Sendable, Hashable, CustomStringConvertible {
  public let name: String
  public let arguments: [TLAValue]
  public init(name: String, arguments: [TLAValue] = []) {
    self.name = name
    self.arguments = arguments
  }
  public var description: String {
    arguments.isEmpty ? name : "\(name)(\(arguments.map(\.description).joined(separator: ", ")))"
  }
}
public struct NamedAction: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let body: ActionExpr
  public let bindings: [ActionBinding]
  public init(name: String, body: ActionExpr, bindings: [ActionBinding] = []) {
    for binding in bindings {
      precondition(
        !binding.name.isEmpty, "Parameterized action '\(name)' requires a parameter name")
      precondition(
        !binding.values.isEmpty,
        "Parameterized action '\(name)' parameter '\(binding.name)' requires a non-empty finite domain"
      )
      precondition(
        Set(binding.values).count == binding.values.count,
        "Parameterized action '\(name)' parameter '\(binding.name)' has duplicate finite-domain values"
      )
    }
    precondition(
      Set(bindings.map(\.name)).count == bindings.count,
      "Parameterized action '\(name)' has duplicate parameter names"
    )
    self.name = name
    self.body = body
    self.bindings = bindings
  }
  public var description: String {
    let parameters = bindings.map(\.name).joined(separator: ", ")
    return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))"): \(body)"
  }
}
func actionInvocations(_ action: NamedAction) -> [(
  invocation: TLAActionInvocation, body: ActionExpr, indices: [Int]
)] {
  func expand(_ position: Int, _ arguments: [TLAValue], _ indices: [Int], _ body: ActionExpr) -> [(
    TLAActionInvocation, ActionExpr, [Int]
  )] {
    guard position < action.bindings.count else {
      return [(TLAActionInvocation(name: action.name, arguments: arguments), body, indices)]
    }
    let binding = action.bindings[position]
    return binding.values.enumerated().flatMap { index, value in
      expand(
        position + 1, arguments + [value], indices + [index],
        substituteVar(binding.name, with: value, in: body))
    }
  }
  return expand(0, [], [], action.body)
}
public struct NamedTemporal: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let expr: TemporalExpr
  public init(name: String, expr: TemporalExpr) {
    self.name = name
    self.expr = expr
  }
  public var description: String { "\(name): \(expr)" }
}
public struct NamedInvariant: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let body: StateExpr
  public init(name: String, body: StateExpr) {
    self.name = name
    self.body = body
  }
  public var description: String { "\(name): \(body)" }
}
public struct ParsedSpecModel: Equatable, Sendable {
  /// The parsed declaration, including its finite initial domain when one was
  /// authored. The domain is part of the formal initial predicate, not display
  /// metadata, so fidelity checks must retain it.
  public let variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]
  public let actions: [(name: String, body: ActionExpr, bindings: [ActionBinding])]
  public let invariants: [(name: String, body: StateExpr)]
  public let temporal: [(name: String, expr: TemporalExpr)]
  public let fairness: [FairnessCondition]
  public let constraint: StateExpr?
  public let imports: [String]
  public let importConfigurations: [FormalModuleConfiguration]
  public let moduleInstances: [FormalModuleInstance]
  public init(
    variables: [(String, TLAValue, StateExpr?)], actions: [(String, ActionExpr, [ActionBinding])],
    invariants: [(String, StateExpr)],
    temporal: [(String, TemporalExpr)] = [],
    fairness: [FairnessCondition] = [],
    constraint: StateExpr? = nil,
    imports: [String] = [],
    importConfigurations: [FormalModuleConfiguration] = [],
    moduleInstances: [FormalModuleInstance] = []
  ) {
    self.variables = variables
    self.actions = actions
    self.invariants = invariants
    self.temporal = temporal
    self.fairness = fairness
    self.constraint = constraint
    self.imports = imports
    self.importConfigurations = importConfigurations
    self.moduleInstances = moduleInstances
  }
  public static func == (lhs: ParsedSpecModel, rhs: ParsedSpecModel) -> Bool {
    guard lhs.variables.count == rhs.variables.count,
      lhs.actions.count == rhs.actions.count,
      lhs.invariants.count == rhs.invariants.count,
      lhs.temporal.count == rhs.temporal.count,
      lhs.fairness == rhs.fairness,
      lhs.constraint == rhs.constraint,
      lhs.imports == rhs.imports,
      lhs.importConfigurations == rhs.importConfigurations,
      lhs.moduleInstances == rhs.moduleInstances
    else { return false }
    for (a, b) in zip(lhs.variables, rhs.variables) {
      if a.name != b.name || a.initial != b.initial || a.initialSet != b.initialSet { return false }
    }
    for (a, b) in zip(lhs.actions, rhs.actions) {
      if a.name != b.name || a.body != b.body || a.bindings != b.bindings { return false }
    }
    for (a, b) in zip(lhs.invariants, rhs.invariants) {
      if a.name != b.name || a.body != b.body { return false }
    }
    for (a, b) in zip(lhs.temporal, rhs.temporal) {
      if a.name != b.name || a.expr != b.expr { return false }
    }
    return true
  }
}
public struct TLASpec: Sendable {
  public let name: String
  public let variables: [NamedVar]
  public let constants: [String: TLAValue]
  public let actions: [NamedAction]
  public let invariants: [NamedInvariant]
  public let temporalProperties: [NamedTemporal]
  public let fairness: [FairnessCondition]
  public let assume: StateExpr?
  public let checkDeadlock: Bool
  public let definitions: [String]
  public let theorems: [String]
  public let extendsModules: String
  public let constraint: StateExpr?
  public let recursiveDefs: [String]
  public let recursiveFuncs: [RecursiveFunc]
  /// Imported modules remain separate source files and resolve their operators at runtime.
  public let imports: [TLASpec]
  /// Model-scoped replacement bindings for imported module operators.
  public let importConfigurations: [FormalModuleConfiguration]
  /// Named source-level TLA+ `INSTANCE` declarations.
  public let moduleInstances: [FormalModuleInstance]
  public var runtimeFuncs: [String: @Sendable ([TLAValue]) -> TLAValue] = [:]
  public var runtimeFuncBodies: [String] = []
  public let symmetrySets: [SymmetrySet]
  public let symmetryGroups: [SymmetryVariableGroup]
  public let symmetricCollections: [SymmetricCollectionDecl]
  public init(
    name: String, variables: [NamedVar], constants: [String: TLAValue] = [:],
    actions: [NamedAction], invariants: [NamedInvariant], temporalProperties: [NamedTemporal] = [],
    fairness: [FairnessCondition] = [], assume: StateExpr? = nil, checkDeadlock: Bool = false,
    definitions: [String] = [], theorems: [String] = [], extendsModules: String = "Integers",
    constraint: StateExpr? = nil, recursiveDefs: [String] = [],
    recursiveFuncs: [RecursiveFunc] = [], imports: [TLASpec] = [],
    importConfigurations: [FormalModuleConfiguration] = [],
    moduleInstances: [FormalModuleInstance] = [], symmetrySets: [SymmetrySet] = [],
    symmetryGroups: [SymmetryVariableGroup] = [],
    symmetricCollections: [SymmetricCollectionDecl] = []
  ) {
    self.name = name
    self.variables = variables
    self.constants = constants
    self.actions = actions
    self.invariants = invariants
    self.temporalProperties = temporalProperties
    self.fairness = fairness
    self.assume = assume
    self.checkDeadlock = checkDeadlock
    self.definitions = definitions
    self.theorems = theorems
    self.extendsModules = extendsModules
    self.constraint = constraint
    self.recursiveDefs = recursiveDefs
    self.recursiveFuncs = recursiveFuncs
    self.imports = imports
    self.importConfigurations = importConfigurations
    self.moduleInstances = moduleInstances
    self.symmetrySets = symmetrySets
    self.symmetryGroups = symmetryGroups
    self.symmetricCollections = symmetricCollections
  }

  /// Recursive definitions visible after resolving the module import graph.
  /// TLA+ `EXTENDS` exports imported operator names into the consumer scope,
  /// so duplicate names are rejected instead of being silently shadowed.
  public var resolvedRecursiveFuncs: [RecursiveFunc] {
    var seen = Set<String>()
    var result: [RecursiveFunc] = []
    func visit(
      _ module: TLASpec,
      replacements: [FormalModuleReplacement],
      path: inout Set<String>
    ) {
      precondition(path.insert(module.name).inserted, "Cyclic formal module import: \(module.name)")
      for imported in module.imports {
        let configuration = module.importConfigurations.first { $0.moduleName == imported.name }
        visit(imported, replacements: configuration?.replacements ?? [], path: &path)
      }
      for function in module.recursiveFuncs {
        precondition(seen.insert(function.name).inserted, "Duplicate imported formal operator: \(function.name)")
        let configuredBody = replacements.reduce(function.body) { body, replacement in
          StateExpr.substituteVariable(replacement.operatorName, with: replacement.expression, in: body)
        }
        result.append(RecursiveFunc(name: function.name, params: function.params, body: configuredBody))
      }
      path.remove(module.name)
    }
    var path = Set<String>()
    visit(self, replacements: [], path: &path)
    return result
  }
  public var description: String {
    var lines = ["Spec \"\(name)\""]
    lines.append("  Variables:")
    for v in variables { lines.append("    \(v)") }
    lines.append("  Actions:")
    for a in actions { lines.append("    \(a)") }
    lines.append("  Invariants:")
    for i in invariants { lines.append("    \(i)") }
    if !temporalProperties.isEmpty {
      lines.append("  Temporal:")
      for t in temporalProperties { lines.append("    \(t.name): \(t.expr)") }
    }
    if !fairness.isEmpty {
      lines.append("  Fairness:")
      for f in fairness { lines.append("    \(f)") }
    }
    return lines.joined(separator: "\n")
  }
  public func extending(_ other: TLASpec, prefix: String? = nil) -> TLASpec {
    let prefixedName = prefix.map { "\($0)!\(name)" } ?? self.name
    let otherVars = other.variables.filter { v in !variables.contains(where: { $0.name == v.name })
    }
    return TLASpec(
      name: prefixedName,
      variables: self.variables + otherVars,
      constants: self.constants.merging(other.constants) { $1 },
      actions: self.actions + other.actions,
      invariants: self.invariants + other.invariants,
      temporalProperties: self.temporalProperties + other.temporalProperties,
      fairness: self.fairness + other.fairness,
      assume: {
        if let a = assume, let b = other.assume { return .and(a, b) }
        return assume ?? other.assume
      }(),
      checkDeadlock: self.checkDeadlock || other.checkDeadlock,
      definitions: self.definitions + other.definitions,
      theorems: self.theorems + other.theorems,
      extendsModules: self.extendsModules,
      constraint: {
        if let a = constraint, let b = other.constraint { return .and(a, b) }
        return constraint ?? other.constraint
      }(),
      recursiveDefs: self.recursiveDefs + other.recursiveDefs,
      recursiveFuncs: self.recursiveFuncs + other.recursiveFuncs,
      imports: self.imports + other.imports,
      moduleInstances: self.moduleInstances + other.moduleInstances,
      symmetrySets: self.symmetrySets + other.symmetrySets,
      symmetryGroups: self.symmetryGroups + other.symmetryGroups,
      symmetricCollections: self.symmetricCollections + other.symmetricCollections
    )
  }
  public func instantiating(_ mapping: [String: TLAValue]) -> TLASpec {
    let constants = self.constants.merging(mapping) { $1 }
    return TLASpec(
      name: self.name,
      variables: self.variables,
      constants: constants,
      actions: self.actions,
      invariants: self.invariants,
      temporalProperties: self.temporalProperties,
      fairness: self.fairness,
      assume: self.assume,
      checkDeadlock: self.checkDeadlock,
      definitions: self.definitions,
      theorems: self.theorems,
      extendsModules: self.extendsModules,
      constraint: self.constraint,
      recursiveDefs: self.recursiveDefs,
      recursiveFuncs: self.recursiveFuncs,
      imports: self.imports,
      moduleInstances: self.moduleInstances,
      symmetrySets: self.symmetrySets,
      symmetryGroups: self.symmetryGroups,
      symmetricCollections: self.symmetricCollections
    )
  }
}
public protocol SpecComponent {}
public struct VarDecl: SpecComponent {
  public let name: String
  public let initial: TLAValue
  public let initialSet: StateExpr?
  public let initExpr: StateExpr?
  public let lazySet: StateExpr?
  public let collectionType: CollectionVarType
  init(_ name: String, _ initial: TLAValue, collectionType: CollectionVarType = .scalar) {
    self.name = name
    self.initial = initial
    self.initialSet = nil
    self.initExpr = nil
    self.lazySet = nil
    self.collectionType = collectionType
  }
  init(
    _ name: String, _ initial: TLAValue, initialSet: StateExpr?,
    collectionType: CollectionVarType = .scalar
  ) {
    self.name = name
    self.initial = initial
    self.initialSet = initialSet
    self.initExpr = nil
    self.lazySet = nil
    self.collectionType = collectionType
  }
  init(_ name: String, initExpr: StateExpr, collectionType: CollectionVarType = .scalar) {
    self.name = name
    self.initial = .int(0)
    self.initialSet = nil
    self.initExpr = initExpr
    self.lazySet = nil
    self.collectionType = collectionType
  }
  init(_ name: String, lazySet: StateExpr, collectionType: CollectionVarType = .scalar) {
    self.name = name
    self.initial = .int(0)
    self.initialSet = nil
    self.initExpr = nil
    self.lazySet = lazySet
    self.collectionType = collectionType
  }
}
public struct ActionDecl: SpecComponent {
  public let name: String
  public let body: ActionExpr
  public let bindings: [ActionBinding]
  init(_ name: String, _ body: ActionExpr, bindings: [ActionBinding] = []) {
    self.name = name
    self.body = body
    self.bindings = bindings
  }
}
public struct InvDecl: SpecComponent {
  public let name: String
  public let body: StateExpr
  init(_ name: String, _ body: StateExpr) {
    self.name = name
    self.body = body
  }
}
public struct TemporalDecl: SpecComponent {
  public let name: String
  public let expr: TemporalExpr
  init(_ name: String, _ expr: TemporalExpr) {
    self.name = name
    self.expr = expr
  }
}
public struct FairnessDecl: SpecComponent {
  public let condition: FairnessCondition
  init(_ condition: FairnessCondition) { self.condition = condition }
}
public struct ConstantDecl: SpecComponent {
  public let name: String
  public let value: TLAValue
  init(_ name: String, _ value: TLAValue) {
    self.name = name
    self.value = value
  }
}
public struct NamedValueDecl: Equatable, Sendable {
  public let name: String
  public let value: TLAValue
}
public struct OpDecl: SpecComponent {
  public let name: String
  public let params: [String]
  public let body: ActionExpr
  init(_ n: String, _ p: [String], _ b: ActionExpr) {
    name = n
    params = p
    body = b
  }
}
public func Operator(
  _ name: String, param: Var<some TLAValueType>, @ActionBuilder body: () -> ActionExpr
) -> OpDecl {
  OpDecl(name, [param.name], body())
}
/// Spec registry for composition via UseSpec().
public enum SpecRegistry {
  nonisolated(unsafe) private static var store: [String: TLASpec] = [:]
  public static func register(_ spec: TLASpec) { store[spec.name] = spec }
  public static func lookup(_ name: String) -> TLASpec? { store[name] }
}
/// Compose a registered spec by name.  Parser handles this at compile time.
public struct UseSpecDecl: SpecComponent {
  public let name: String
  init(_ n: String) { name = n }
}
public func UseSpec(_ name: String) -> UseSpecDecl { UseSpecDecl(name) }
public struct OpUse: SpecComponent {
  public let op: String
  public let param: String
  public let varName: String
  public let value: TLAValue?
  init(_ o: String, _ p: String, _ v: String, _ val: TLAValue? = nil) {
    op = o
    param = p
    varName = v
    value = val
  }
}
public func UseOp(_ operatorName: String, with variable: Var<some TLAValueType>) -> OpUse {
  OpUse(operatorName, "", variable.name)
}
public func UseOp(_ operatorName: String, value: some TLAValueConvertible) -> OpUse {
  OpUse(operatorName, "", "", value.tlaValue)
}
public struct DefinitionDecl: SpecComponent, Equatable {
  public let tlaText: String
  public let name: String?
  public let body: StateExpr?
  init(_ tlaText: String) {
    self.tlaText = tlaText
    self.name = nil
    self.body = nil
  }
  init(name: String, body: StateExpr) {
    self.tlaText = ""
    self.name = name
    self.body = body
  }
}
public struct TheoremDecl: SpecComponent, Equatable {
  public let tlaText: String
  public let name: String?
  public let temporalBody: TemporalExpr?
  public let stateBody: StateExpr?
  init(_ tlaText: String) {
    self.tlaText = tlaText
    self.name = nil
    self.temporalBody = nil
    self.stateBody = nil
  }
  init(name: String, temporal: TemporalExpr) {
    self.tlaText = ""
    self.name = name
    self.temporalBody = temporal
    self.stateBody = nil
  }
  init(name: String, state: StateExpr) {
    self.tlaText = ""
    self.name = name
    self.temporalBody = nil
    self.stateBody = state
  }
}
public struct AssumeDecl: SpecComponent, Equatable {
  public let expr: StateExpr
  init(_ expr: StateExpr) { self.expr = expr }
}
public struct ExtendsDecl: SpecComponent, Equatable {
  public let modules: String
  init(_ modules: String) { self.modules = modules }
}
public struct UseDecl: SpecComponent {
  public let spec: TLASpec
  init(_ spec: TLASpec) { self.spec = spec }
}

public struct ConstraintDecl: SpecComponent, Equatable {
  public let body: StateExpr
  init(_ body: StateExpr) { self.body = body }
}
public struct RecursiveDecl: SpecComponent, Equatable {
  public let tlaText: String
  init(_ tlaText: String) { self.tlaText = tlaText }
}
public struct RecursiveFunc: Sendable, Equatable {
  public let name: String
  public let params: [String]
  public let body: StateExpr
  public init(name: String, params: [String], body: StateExpr) {
    self.name = name
    self.params = params
    self.body = body
  }
}
public struct RecursiveFuncDecl: SpecComponent, Equatable {
  public let funcDef: RecursiveFunc
  init(_ funcDef: RecursiveFunc) { self.funcDef = funcDef }
}
/// Runtime recursive function — evaluated by calling actual Swift closure.
public struct RuntimeFuncDecl: SpecComponent {
  public let name: String
  public let tlaBody: String  // TLA+ output
  public let implementation: @Sendable ([TLAValue]) -> TLAValue
  public init(
    name: String, tlaBody: String, implementation: @escaping @Sendable ([TLAValue]) -> TLAValue
  ) {
    self.name = name
    self.tlaBody = tlaBody
    self.implementation = implementation
  }
}
extension RuntimeFuncDecl: Equatable {
  public static func == (lhs: RuntimeFuncDecl, rhs: RuntimeFuncDecl) -> Bool {
    lhs.name == rhs.name && lhs.tlaBody == rhs.tlaBody
  }
}
@resultBuilder
public enum SpecBuilder {
  public static func buildBlock(_ components: [SpecComponent]...) -> [SpecComponent] {
    components.flatMap { $0 }
  }
  public static func buildExpression(_ expr: VarDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ActionDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: InvDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: TemporalDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: FairnessDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ConstantDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: DefinitionDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: TheoremDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: AssumeDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ExtendsDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: UseDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ImportDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ModuleInstanceDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: UseSpecDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: DeadlockDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ConstraintDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: RecursiveDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: RecursiveFuncDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: RuntimeFuncDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: SymmetrySetDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: SymmetryVariableGroupDecl) -> [SpecComponent] {
    [expr]
  }
  public static func buildExpression(_ expr: SymmetricCollectionDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: NamedValueDecl) -> [SpecComponent] { [] }
  public static func buildExpression(_ expr: OpDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: OpUse) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: Algorithm) -> [SpecComponent] { [expr] }
  public static func buildExpression<T: TLAValueType>(_ expr: Var<T>) -> [SpecComponent] {
    guard let initial = expr.initial else { return [] }
    return [VarDecl(expr.name, initial)]
  }
  public static func buildOptional(_ component: [SpecComponent]?) -> [SpecComponent] {
    component ?? []
  }
  public static func buildEither(first: [SpecComponent]) -> [SpecComponent] { first }
  public static func buildEither(second: [SpecComponent]) -> [SpecComponent] { second }
  public static func buildArray(_ components: [[SpecComponent]]) -> [SpecComponent] {
    components.flatMap { $0 }
  }
}
/// Generate DSL elements for each value in a sequence.
/// `ForEach([pPhase1, pPhase2, pPhase3]) { p in Action(...) }`
public func ForEach<C: Sequence>(_ values: C, @SpecBuilder _ body: (C.Element) -> [SpecComponent])
  -> [SpecComponent] {
  values.flatMap(body)
}
@resultBuilder
public enum InvariantBuilder {
  public static func buildBlock(_ components: StateExpr...) -> StateExpr {
    if components.isEmpty { return .value(.bool(true)) }
    return components.dropFirst().reduce(components[0]) { .and($0, $1) }
  }
  public static func buildExpression(_ expr: StateExpr) -> StateExpr { expr }
  public static func buildOptional(_ component: StateExpr?) -> StateExpr {
    component ?? .value(.bool(true))
  }
  public static func buildEither(first: StateExpr) -> StateExpr { first }
  public static func buildEither(second: StateExpr) -> StateExpr { second }
  public static func buildArray(_ components: [StateExpr]) -> StateExpr {
    if components.isEmpty { return .value(.bool(true)) }
    return components.dropFirst().reduce(components[0]) { .and($0, $1) }
  }
}
@resultBuilder
public enum ActionBuilder {
  public static func buildBlock(_ components: ActionExpr...) -> ActionExpr {
    if components.isEmpty { return .guard_(.value(.bool(true))) }
    return components.dropFirst().reduce(components[0]) { .and($0, $1) }
  }
  public static func buildExpression(_ expr: ActionExpr) -> ActionExpr { expr }
  public static func buildExpression(_ expr: StateExpr) -> ActionExpr { .guard_(expr) }
  public static func buildOptional(_ component: ActionExpr?) -> ActionExpr {
    component ?? .guard_(.value(.bool(true)))
  }
  public static func buildEither(first: ActionExpr) -> ActionExpr { first }
  public static func buildEither(second: ActionExpr) -> ActionExpr { second }
}
@discardableResult
public func Variable(_ name: String, _ initial: some TLAValueConvertible) -> VarDecl {
  VarDecl(name, initial.tlaValue)
}
@discardableResult
public func Variable(_ name: String, in values: some Sequence<some TLAValueConvertible>) -> VarDecl {
  let set = Set(values.map(\.tlaValue))
  let stateSet: StateExpr = .setLiteral(set.map { .value($0) })
  return VarDecl(name, .set(set), initialSet: stateSet)
}
@discardableResult
public func Variable<T>(_ ref: Var<T>) -> VarDecl {
  VarDecl(ref.name, ref.initial ?? .int(0))
}
@discardableResult
public func Variable<T>(_ ref: Var<T>, _ initial: some TLAValueConvertible) -> VarDecl {
  VarDecl(ref.name, initial.tlaValue)
}
@discardableResult
public func Variable<T>(_ ref: Var<T>, in values: some Sequence<some TLAValueConvertible>)
  -> VarDecl {
  let set = Set(values.map(\.tlaValue))
  let stateSet: StateExpr = .setLiteral(set.map { .value($0) })
  return VarDecl(ref.name, .set(set), initialSet: stateSet)
}
/// Expression-backed nondeterministic init. The range is evaluated when initial
/// states are computed instead of being materialized while building the spec.
@discardableResult
public func Variable(from name: String, _ range: StateExpr) -> VarDecl {
  VarDecl(name, lazySet: range)
}
// MARK: - Shared initial state computation
public func computeInitialStates(_ spec: TLASpec) -> [[String: TLAValue]] {
  let substituted = substituteConstants(spec)
  let base = Dictionary(uniqueKeysWithValues: substituted.variables.map { ($0.name, $0.initial) })
  let nondeterministic = substituted.variables.filter { $0.initialSet != nil || $0.lazySet != nil }
  var states = nondeterministic.reduce(into: [base]) { states, variable in
    states = states.flatMap { state -> [[String: TLAValue]] in
      let expression = variable.lazySet ?? variable.initialSet
      guard let expression,
        case .set(let values) = try? expression.evaluate(
          in: state,
          runtimeFuncs: substituted.runtimeFuncs,
          recursiveFuncs: substituted.resolvedRecursiveFuncs
        )
      else { return [] }
      return TLAValue.sorted(values).map {
        state.merging([variable.name: $0]) { _, new in new }
      }
    }
  }
  for variable in substituted.variables where variable.initExpr != nil {
    states = states.compactMap { state in
      guard let val = try? variable.initExpr!.evaluate(
        in: state,
        runtimeFuncs: substituted.runtimeFuncs,
        recursiveFuncs: substituted.resolvedRecursiveFuncs
      ) else { return nil }
      var s = state
      s[variable.name] = val
      return s
    }
  }
  return states
}
@discardableResult
public func Action(_ name: String, @ActionBuilder _ body: () -> ActionExpr) -> ActionDecl {
  ActionDecl(name, body())
}
@discardableResult
public func Action(
  _ name: String,
  parameters: [any ActionParameterDescriptor],
  @ActionBuilder _ body: () -> ActionExpr
) -> ActionDecl {
  ActionDecl(name, body(), bindings: parameters.map(\.actionBinding))
}
public func Invariant(_ name: String, @InvariantBuilder _ body: () -> StateExpr) -> InvDecl {
  InvDecl(name, body())
}
public func LeadsTo(_ name: String, _ from: StateExpr, _ to: StateExpr) -> TemporalDecl {
  TemporalDecl(name, .leadsTo(from, to))
}
public func Eventually(_ name: String, _ expr: StateExpr) -> TemporalDecl {
  TemporalDecl(name, .eventually(expr))
}
public func Always(_ name: String, _ expr: StateExpr) -> TemporalDecl {
  TemporalDecl(name, .always(expr))
}
public func AlwaysEventually(_ name: String, _ expr: StateExpr) -> TemporalDecl {
  TemporalDecl(name, .alwaysEventually(expr))
}
public func EventuallyAlways(_ name: String, _ expr: StateExpr) -> TemporalDecl {
  TemporalDecl(name, .eventuallyAlways(expr))
}
public func WeakFairness(_ action: String) -> FairnessDecl {
  FairnessDecl(.weakFairness(action))
}
public func StrongFairness(_ action: String) -> FairnessDecl {
  FairnessDecl(.strongFairness(action))
}
@discardableResult
public func Variable<T>(computed ref: Var<T>, @InvariantBuilder _ body: () -> StateExpr) -> VarDecl {
  VarDecl(ref.name, initExpr: body())
}
public struct DeadlockDecl: SpecComponent { init() {} }
public func DeadlockCheck() -> DeadlockDecl { DeadlockDecl() }
public struct SymmetrySet: Hashable, Sendable, CustomStringConvertible {
  public let variableName: String
  public let values: Set<TLAValue>
  public init(variableName: String, values: Set<TLAValue>) {
    self.variableName = variableName
    self.values = values
  }
  public var description: String { "SYMMETRY \(variableName)" }
  func canonicalize(_ state: [String: TLAValue]) -> [String: TLAValue] {
    let sorted = values.sorted { $0.description < $1.description }
    let present = sorted.filter { val in stateContains(state, val) }
    guard !present.isEmpty else { return state }
    let canonical = sorted[0]
    let mapping: [TLAValue: TLAValue] = Dictionary(
      uniqueKeysWithValues:
        present.map { ($0, canonical) }
    )
    return state.mapValues { applyMapping($0, mapping) }
  }
}
public func Constant(_ name: String, _ value: some TLAValueConvertible) -> ConstantDecl {
  ConstantDecl(name, value.tlaValue)
}
/// Register a named value constant for use in spec expressions.
/// `Value("poweredOn", 5)` makes `poweredOn` resolve to 5 in spec expressions.
public func Value(_ name: String, _ value: some TLAValueConvertible) -> NamedValueDecl {
  NamedValueDecl(name: name, value: value.tlaValue)
}
public func Definition(_ tlaText: String) -> DefinitionDecl {
  DefinitionDecl(tlaText)
}
public func Definition(_ name: String, @InvariantBuilder _ body: () -> StateExpr) -> DefinitionDecl {
  DefinitionDecl(name: name, body: body())
}
public func Theorem(_ tlaText: String) -> TheoremDecl {
  TheoremDecl(tlaText)
}
public func Theorem(name: String, @InvariantBuilder always: () -> StateExpr) -> TheoremDecl {
  TheoremDecl(name: name, state: always())
}
public func Theorem(name: String, always state: StateExpr) -> TheoremDecl {
  TheoremDecl(name: name, state: state)
}
public func Theorem(name: String, temporal: TemporalExpr) -> TheoremDecl {
  TheoremDecl(name: name, temporal: temporal)
}
public func Assume(_ expr: some StateExprConvertible) -> AssumeDecl {
  AssumeDecl(expr.stateExpr)
}
public func Extends(_ modules: String) -> ExtendsDecl {
  ExtendsDecl(modules)
}
public func Constraint(_ expr: some StateExprConvertible) -> ConstraintDecl {
  ConstraintDecl(expr.stateExpr)
}
public func Recursive(_ tlaText: String) -> RecursiveDecl {
  RecursiveDecl(tlaText)
}
public func Use(spec: TLASpec) -> UseDecl {
  UseDecl(spec)
}
public func DefineRecursive(
  _ name: String, params: [String], @InvariantBuilder body: () -> StateExpr
) -> RecursiveFuncDecl {
  RecursiveFuncDecl(RecursiveFunc(name: name, params: params, body: body()))
}
public func RuntimeFunc(
  _ name: String, tlaBody: String, _ implementation: @escaping @Sendable ([TLAValue]) -> TLAValue
) -> RuntimeFuncDecl {
  RuntimeFuncDecl(name: name, tlaBody: tlaBody, implementation: implementation)
}

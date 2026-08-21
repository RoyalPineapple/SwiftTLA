public enum CollectionVarType: Sendable, Equatable {
  case scalar
  case set
  case array(Int)
  case dictionary(Int)
}

enum VariableOrigin: Sendable, Equatable {
  case source
  case compiler
  case programCounter
}

public struct NamedVar: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let initial: TLAValue
  public let initialSet: StateExpr?
  public let initExpr: StateExpr?
  public let lazySet: StateExpr?  // expression-backed nondeterministic init
  public let collectionType: CollectionVarType
  let origin: VariableOrigin

  public init(
    name: String, initial: TLAValue, initialSet: StateExpr? = nil, initExpr: StateExpr? = nil,
    lazySet: StateExpr? = nil, collectionType: CollectionVarType = .scalar
  ) {
    self.init(
      name: name,
      initial: initial,
      initialSet: initialSet,
      initExpr: initExpr,
      lazySet: lazySet,
      collectionType: collectionType,
      origin: .source
    )
  }

  init(
    name: String, initial: TLAValue, initialSet: StateExpr? = nil, initExpr: StateExpr? = nil,
    lazySet: StateExpr? = nil, collectionType: CollectionVarType = .scalar,
    origin: VariableOrigin
  ) {
    self.name = name
    self.initial = initial
    self.initialSet = initialSet
    self.initExpr = initExpr
    self.lazySet = lazySet
    self.collectionType = collectionType
    self.origin = origin
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
func formalActionCall(named name: String, arguments: [TLAValue]) -> String {
  arguments.isEmpty ? name : "\(name)(\(arguments.map(\.description).joined(separator: ", ")))"
}

/// One formal action with concrete argument values at a source or tool boundary.
public struct FormalActionCall: Sendable, Hashable, CustomStringConvertible {
  public let name: String
  public let arguments: [TLAValue]
  public init(name: String, arguments: [TLAValue] = []) {
    self.name = name
    self.arguments = arguments
  }
  public var description: String {
    formalActionCall(named: name, arguments: arguments)
  }
}
public struct NamedAction: Sendable, CustomStringConvertible, Equatable {
  public let name: String
  public let body: ActionExpr
  public let bindings: [ActionBinding]
  let sourceIssue: SourceModelIssue?
  let controlOwner: ControlOwner?

  public init(name: String, body: ActionExpr, bindings: [ActionBinding] = []) {
    self.init(name: name, body: body, bindings: bindings, controlOwner: nil)
  }

  init(
    name: String,
    body: ActionExpr,
    bindings: [ActionBinding] = [],
    controlOwner: ControlOwner?
  ) {
    self.name = name
    self.body = body
    self.bindings = bindings
    self.sourceIssue = Self.bindingIssue(action: name, bindings: bindings)
    self.controlOwner = controlOwner
  }

  private static func bindingIssue(action: String, bindings: [ActionBinding]) -> SourceModelIssue? {
    var names = Set<String>()
    for binding in bindings {
      guard !binding.name.isEmpty else {
        return .actionBinding(action: action, parameter: nil, problem: "a parameter has no name")
      }
      guard !binding.values.isEmpty else {
        return .actionBinding(action: action, parameter: binding.name, problem: "the domain is empty")
      }
      guard Set(binding.values).count == binding.values.count else {
        return .actionBinding(action: action, parameter: binding.name, problem: "the domain contains duplicate values")
      }
      guard names.insert(binding.name).inserted else {
        return .actionBinding(action: action, parameter: binding.name, problem: "the name is declared more than once")
      }
    }
    return nil
  }
  public var description: String {
    let parameters = bindings.map(\.name).joined(separator: ", ")
    return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))"): \(body)"
  }
}
func actionVariants(_ action: NamedAction) -> [(
  arguments: [TLAValue], body: ActionExpr, indices: [Int]
)] {
  func expand(_ position: Int, _ arguments: [TLAValue], _ indices: [Int], _ body: ActionExpr) -> [(
    [TLAValue], ActionExpr, [Int]
  )] {
    guard position < action.bindings.count else {
      return [(arguments, body, indices)]
    }
    let binding = action.bindings[position]
    return binding.values.enumerated().flatMap { index, value in
      expand(
        position + 1, arguments + [value], indices + [index],
        body.substitutingVariable(binding.name, with: .value(value)))
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

extension Array where Element == ConstantDecl {
  func value(named name: String) -> TLAValue? {
    first { $0.name == name }?.value
  }

  func replacing(with replacements: [ConstantDecl]) -> [ConstantDecl] {
    filter { current in !replacements.contains { $0.name == current.name } } + replacements
  }
}
struct RenderedModuleDefinition: Sendable, Equatable {
  let name: String?
  let text: String
  let dependencies: [String]

  init(name: String? = nil, text: String, dependencies: [String] = []) {
    self.name = name
    self.text = text
    self.dependencies = dependencies
  }
}
public enum StandardModule: String, Sendable, Hashable, CaseIterable {
  case integers = "Integers"
  case naturals = "Naturals"
  case finiteSets = "FiniteSets"
  case sequences = "Sequences"
  case tlc = "TLC"
}

private func canonicalStandardModules(_ modules: [StandardModule]) -> [StandardModule] {
  modules.reduce(into: []) { result, module in
    if !result.contains(module) { result.append(module) }
  }
}

public struct TLASpec: Sendable {
  enum AlgorithmPhase: Sendable, Equatable {
    case source
    case lowered
  }
  public let name: String
  public let variables: [NamedVar]
  public let constants: [ConstantDecl]
  /// Parameters supplied by a named TLA+ `INSTANCE … WITH` declaration.
  public let formalParameters: [FormalModuleParameter]
  public let actions: [NamedAction]
  public let invariants: [NamedInvariant]
  public let temporalProperties: [NamedTemporal]
  public let fairness: [FairnessCondition]
  public let assume: StateExpr?
  public let checkDeadlock: Bool
  public let theorems: [TheoremDecl]
  public let extendsModules: [StandardModule]
  public let constraint: StateExpr?
  public let recursiveFuncs: [RecursiveFunc]
  /// Executable, higher-order operator definitions. These remain formal AST
  /// data so the checker and runtime apply the same semantics.
  public let formalOperatorDefinitions: [FormalOperatorDefinition]
  /// Imported modules remain separate source files and resolve their operators at runtime.
  public let imports: [TLASpec]
  /// Model-scoped replacement bindings for imported module operators.
  public let importConfigurations: [FormalModuleConfiguration]
  /// Named source-level TLA+ `INSTANCE` declarations.
  public let moduleInstances: [FormalModuleInstance]
  public let refinements: [RefinementDecl]
  public let requiredCapabilities: [FormalCapability]
  public let symmetrySets: [SymmetrySet]
  public let symmetricCollections: [SymmetricCollectionDecl]
  /// Opaque source-level Algorithm evidence. This is distinct from the
  /// lowered variables/actions and never exposes the Algorithm IR.
  let algorithmFidelityTokens: [AlgorithmFidelityToken]
  /// Canonical Algorithm declarations retained solely for source rendering.
  ///
  /// The formal runtime still uses the one lowered `TLASpec` representation.
  /// Keeping these declarations lets a tooling boundary render the exact
  /// authored Algorithm as PlusCal without reconstructing it from TLA+ AST.
  let sourceAlgorithms: [Algorithm]
  var algorithmPhase: AlgorithmPhase
  public init(
    name: String, variables: [NamedVar], constants: [ConstantDecl] = [],
    formalParameters: [FormalModuleParameter] = [],
    actions: [NamedAction], invariants: [NamedInvariant], temporalProperties: [NamedTemporal] = [],
    fairness: [FairnessCondition] = [], assume: StateExpr? = nil, checkDeadlock: Bool = false,
    theorems: [TheoremDecl] = [], extendsModules: [StandardModule] = [.integers],
    constraint: StateExpr? = nil,
    recursiveFuncs: [RecursiveFunc] = [],
    formalOperatorDefinitions: [FormalOperatorDefinition] = [], imports: [TLASpec] = [],
    importConfigurations: [FormalModuleConfiguration] = [],
    moduleInstances: [FormalModuleInstance] = [], refinements: [RefinementDecl] = [], requiredCapabilities: [FormalCapability] = [], symmetrySets: [SymmetrySet] = [],
    symmetricCollections: [SymmetricCollectionDecl] = [],
    algorithmFidelityTokens: [AlgorithmFidelityToken] = [],
    sourceAlgorithms: [Algorithm] = []
  ) {
    self.name = name
    self.variables = variables
    self.constants = constants
    self.formalParameters = formalParameters
    self.actions = actions
    self.invariants = invariants
    self.temporalProperties = temporalProperties
    self.fairness = fairness
    self.assume = assume
    self.checkDeadlock = checkDeadlock
    self.theorems = theorems
    self.extendsModules = canonicalStandardModules(extendsModules)
    self.constraint = constraint
    self.recursiveFuncs = recursiveFuncs
    self.formalOperatorDefinitions = formalOperatorDefinitions
    self.imports = imports
    self.importConfigurations = importConfigurations
    self.moduleInstances = moduleInstances
    self.refinements = refinements
    self.requiredCapabilities = requiredCapabilities
    self.symmetrySets = symmetrySets
    self.symmetricCollections = symmetricCollections
    self.algorithmFidelityTokens = algorithmFidelityTokens
    self.sourceAlgorithms = sourceAlgorithms
    self.algorithmPhase = sourceAlgorithms.isEmpty ? .lowered : .source
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
}
public protocol SpecComponent {}
/// The legal source section for a declaration in an authored PlusCal module.
public enum AuthoredPlusCalDeclarationPhase: Sendable, Hashable {
  case prelude
  case define
}

/// Structural placement and dependency metadata retained for authored PlusCal.
struct AuthoredPlusCalDeclaration: Sendable, Equatable {
  let name: String?
  let text: String
  let phase: AuthoredPlusCalDeclarationPhase
  let dependencies: [String]

  init(name: String? = nil, text: String, phase: AuthoredPlusCalDeclarationPhase = .prelude, dependencies: [String] = []) {
    self.name = name
    self.text = text
    self.phase = phase
    self.dependencies = dependencies
  }
}
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
public struct ConstantDecl: SpecComponent, Sendable, Equatable {
  public let name: String
  public let value: TLAValue
  public init(_ name: String, _ value: TLAValue) {
    self.name = name
    self.value = value
  }
}
public enum FormalModuleParameterKind: String, Sendable, Equatable {
  /// Emits a TLA+ `CONSTANTS` declaration.
  case constant
  /// Emits a TLA+ `VARIABLES` declaration. This is used when an instance
  /// substitutes a state-level module symbol, as `ClientCentric` does for
  /// `Keys` and `Values`.
  case variable
}

public struct FormalModuleParameter: SpecComponent, StateExprConvertible, Sendable, Equatable {
  public let name: String
  public let kind: FormalModuleParameterKind

  public init(_ name: String, kind: FormalModuleParameterKind = .constant) {
    self.name = name
    self.kind = kind
  }

  public var stateExpr: StateExpr { .variable(name) }
}
/// A named formal operator that stays executable in the SwiftTLA AST.
public struct FormalOperatorDecl: SpecComponent, Equatable {
  public let definition: FormalOperatorDefinition

  public init(_ definition: FormalOperatorDefinition) {
    self.definition = definition
  }

  var tlaText: String {
    let parameters = definition.parameters.map { parameter in
      switch parameter {
      case .value(let name): return name
      case .operator(let name, let arity):
        return "\(name)(\(Array(repeating: "_", count: arity).joined(separator: ", ")))"
      }
    }.joined(separator: ", ")
    let declaration = parameters.isEmpty ? definition.name : "\(definition.name)(\(parameters))"
    return "\(declaration) == \(definition.body)"
  }
}

public func FormalDefinition(
  _ name: String,
  parameters: [FormalParameter],
  body: StateExpr,
  plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
  dependsOn: [String] = []
) -> FormalOperatorDecl {
  FormalOperatorDecl(FormalOperatorDefinition(name: name, parameters: parameters, body: body, plusCalPhase: plusCalPhase, plusCalDependencies: dependsOn))
}

public func FormalDefinition<Body: StateExprConvertible>(
  _ name: String,
  parameters: [FormalParameter],
  body: Body,
  plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
  dependsOn: [String] = []
) -> FormalOperatorDecl {
  FormalOperatorDecl(FormalOperatorDefinition(name: name, parameters: parameters, body: body.stateExpr, plusCalPhase: plusCalPhase, plusCalDependencies: dependsOn))
}

/// Declares a unary executable formal operator without exposing raw AST values.
public func FormalDefinition<Input: TLAValueType>(
  _ name: String,
  taking: Input.Type,
  plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
  dependsOn: [String] = [],
  body: (Expr<Input>) -> some StateExprConvertible
) -> FormalOperatorDecl {
  let parameter = "value0"
  return FormalOperatorDecl(FormalOperatorDefinition(
    name: name,
    parameters: [.value(parameter)],
    body: body(Expr<Input>(.variable(parameter))).stateExpr,
    plusCalPhase: plusCalPhase,
    plusCalDependencies: dependsOn
  ))
}

/// Declares a binary executable formal operator without exposing raw AST values.
public func FormalDefinition<First: TLAValueType, Second: TLAValueType>(
  _ name: String,
  taking: First.Type,
  _ second: Second.Type,
  plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
  dependsOn: [String] = [],
  body: (Expr<First>, Expr<Second>) -> some StateExprConvertible
) -> FormalOperatorDecl {
  let first = "value0"
  let second = "value1"
  return FormalOperatorDecl(FormalOperatorDefinition(
    name: name,
    parameters: [.value(first), .value(second)],
    body: body(Expr<First>(.variable(first)), Expr<Second>(.variable(second))).stateExpr,
    plusCalPhase: plusCalPhase,
    plusCalDependencies: dependsOn
  ))
}
public struct TheoremDecl: SpecComponent, Equatable {
  public let name: String
  public let temporalBody: TemporalExpr?
  public let stateBody: StateExpr?
  init(name: String, temporal: TemporalExpr) {
    self.name = name
    self.temporalBody = temporal
    self.stateBody = nil
  }
  init(name: String, state: StateExpr) {
    self.name = name
    self.temporalBody = nil
    self.stateBody = state
  }
}

/// A named refinement of this specification by a module-instance specification.
public struct RefinementDecl: SpecComponent, Sendable, Equatable {
  public enum Operator: Sendable, Equatable {
    case spec
    case liveSpec
    case liveSpecEquals

    init?(sourceName: String) {
      switch sourceName {
      case "spec": self = .spec
      case "liveSpec": self = .liveSpec
      case "liveSpecEquals": self = .liveSpecEquals
      default: return nil
      }
    }
  }

  public let name: String
  public let instance: FormalModuleInstanceReference
  public let `operator`: Operator
  public let mappings: [RefinementMapping]

  init(
    name: String,
    instance: FormalModuleInstanceReference,
    operator: Operator,
    mappings: [RefinementMapping]
  ) {
    self.name = name
    self.instance = instance
    self.operator = `operator`
    self.mappings = mappings
  }
}

extension RefinementDecl {
  var renderedFormalDeclaration: String {
    let target: String
    switch `operator` {
    case .spec: target = "Spec"
    case .liveSpec: target = "LiveSpec"
    case .liveSpecEquals: target = "LiveSpecEquals"
    }
    return "\(name) == \(instance.namespace)!\(target)"
  }
}

/// One explicit source expression for an abstract module variable or parameter.
public struct RefinementMapping: Sendable, Equatable {
  public let target: String
  public let source: StateExpr

  public init<Value>(_ target: Var<Value>, from source: some StateExprConvertible) {
    self.target = target.name
    self.source = source.stateExpr
  }

  public init(_ target: FormalModuleParameter, from source: some StateExprConvertible) {
    self.target = target.name
    self.source = source.stateExpr
  }

  init(target: String, source: StateExpr) {
    self.target = target
    self.source = source
  }
}

public func Refinement(
  name: String,
  instance: FormalModuleInstance,
  operator: RefinementDecl.Operator = .spec,
  mappings: [RefinementMapping]
) -> RefinementDecl {
  RefinementDecl(
    name: name,
    instance: instance.reference,
    operator: `operator`,
    mappings: mappings
  )
}

public enum FormalCapability: String, Sendable, Equatable {
  case temporalFairnessSpecification
  case temporalEquivalence
}

public struct CapabilityRequirement: SpecComponent, Sendable, Equatable {
  public let capability: FormalCapability
  init(_ capability: FormalCapability) { self.capability = capability }
}

public func RequireCapability(_ capability: FormalCapability) -> CapabilityRequirement { .init(capability) }

extension TLASpec {
  func instanceArguments(for instance: FormalModuleInstance) -> [ModuleArgument] {
    guard let refinement = refinements.first(where: { $0.instance.resolves(instance) }) else {
      return instance.arguments
    }
    return refinement.mappings.map { .init($0.target, expression: $0.source) }
  }
}
public struct AssumeDecl: SpecComponent, Equatable {
  public let expr: StateExpr
  init(_ expr: StateExpr) { self.expr = expr }
}
public struct ExtendsDecl: SpecComponent, Equatable {
  public let modules: [StandardModule]
  init(_ modules: [StandardModule]) { self.modules = modules }
}
public struct ConstraintDecl: SpecComponent, Equatable {
  public let body: StateExpr
  init(_ body: StateExpr) { self.body = body }
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
  public static func buildExpression(_ expr: FormalModuleParameter) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: FormalOperatorDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: TheoremDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: AssumeDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ExtendsDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ImportDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: FormalModuleInstance) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: RefinementDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: CapabilityRequirement) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: DeadlockDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: ConstraintDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: RecursiveFuncDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: SymmetrySetDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: SymmetricCollectionDecl) -> [SpecComponent] { [expr] }
  public static func buildExpression(_ expr: Algorithm) -> [SpecComponent] { [expr] }
  public static func buildExpression<T: TLAValueType>(_ expr: Var<T>) -> [SpecComponent] {
    if let issue = expr.sourceIssue {
      return [VarDecl(expr.name, initExpr: .sourceIssue(issue))]
    }
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
  public static func buildExpression(_ expr: Expr<Bool>) -> StateExpr { expr.raw }
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
  if let issue = initial.sourceIssue {
    return VarDecl(name, initExpr: .sourceIssue(issue))
  }
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
  if let issue = ref.sourceIssue {
    return VarDecl(ref.name, initExpr: .sourceIssue(issue))
  }
  VarDecl(ref.name, ref.initial ?? .int(0))
}
@discardableResult
public func Variable<T>(_ ref: Var<T>, _ initial: some TLAValueConvertible) -> VarDecl {
  if let issue = initial.sourceIssue {
    return VarDecl(ref.name, initExpr: .sourceIssue(issue))
  }
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
public func WeakFairnessNext() -> FairnessDecl {
  FairnessDecl(.weakFairnessNext)
}
public func StrongFairnessNext() -> FairnessDecl {
  FairnessDecl(.strongFairnessNext)
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
}
public func Constant(_ name: String, _ value: some TLAValueConvertible) -> ConstantDecl {
  ConstantDecl(name, value.tlaValue)
}
/// Declares a module symbol that an `Instance` supplies with a `ModuleArgument`.
public func Parameter(
  _ name: String,
  kind: FormalModuleParameterKind = .constant
) -> FormalModuleParameter {
  FormalModuleParameter(name, kind: kind)
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
public func Extends(_ modules: StandardModule...) -> ExtendsDecl {
  ExtendsDecl(modules)
}
public func Constraint(_ expr: some StateExprConvertible) -> ConstraintDecl {
  ConstraintDecl(expr.stateExpr)
}
public func DefineRecursive(
  _ name: String, params: [String], @InvariantBuilder body: () -> StateExpr
) -> RecursiveFuncDecl {
  RecursiveFuncDecl(RecursiveFunc(name: name, params: params, body: body()))
}

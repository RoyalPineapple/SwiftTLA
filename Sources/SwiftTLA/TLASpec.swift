public struct NamedVar: Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let initial: TLAValue
    public let initialSet: StateExpr?
    public let initExpr: StateExpr?  // computed from other initial vars
    public init(name: String, initial: TLAValue, initialSet: StateExpr? = nil, initExpr: StateExpr? = nil) {
        self.name = name; self.initial = initial; self.initialSet = initialSet; self.initExpr = initExpr
    }
    public var description: String {
        if let s = initialSet { return "\(name) \\in \(s)" }
        return "\(name) = \(initial)"
    }
}

public struct NamedAction: Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let body: ActionExpr
    public init(name: String, body: ActionExpr) {
        self.name = name
        self.body = body
    }
    public var description: String { "\(name): \(body)" }
}

public struct NamedTemporal: Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let expr: TemporalExpr
    public init(name: String, expr: TemporalExpr) { self.name = name; self.expr = expr }
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
    public var runtimeFuncs: [String: @Sendable ([TLAValue]) -> TLAValue] = [:]
    public var runtimeFuncBodies: [String] = []
    public let symmetrySets: [SymmetrySet]
    public let symmetryGroups: [SymmetryVariableGroup]

    public init(name: String, variables: [NamedVar], constants: [String: TLAValue] = [:], actions: [NamedAction], invariants: [NamedInvariant], temporalProperties: [NamedTemporal] = [], fairness: [FairnessCondition] = [], assume: StateExpr? = nil, checkDeadlock: Bool = false, definitions: [String] = [], theorems: [String] = [], extendsModules: String = "Integers", constraint: StateExpr? = nil, recursiveDefs: [String] = [], recursiveFuncs: [RecursiveFunc] = [], symmetrySets: [SymmetrySet] = [], symmetryGroups: [SymmetryVariableGroup] = []) {
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
        self.symmetrySets = symmetrySets
        self.symmetryGroups = symmetryGroups
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
        let otherVars = other.variables.filter { v in !variables.contains(where: { $0.name == v.name }) }
        return TLASpec(
            name: prefixedName,
            variables: self.variables + otherVars,
            constants: self.constants.merging(other.constants) { $1 },
            actions: self.actions + other.actions,
            invariants: self.invariants + other.invariants,
            temporalProperties: self.temporalProperties + other.temporalProperties,
            fairness: self.fairness + other.fairness,
            assume: { if let a = assume, let b = other.assume { return .and(a, b) }; return assume ?? other.assume }(),
            checkDeadlock: self.checkDeadlock || other.checkDeadlock,
            definitions: self.definitions + other.definitions,
            theorems: self.theorems + other.theorems,
            extendsModules: self.extendsModules,
            constraint: { if let a = constraint, let b = other.constraint { return .and(a, b) }; return constraint ?? other.constraint }(),
            recursiveDefs: self.recursiveDefs + other.recursiveDefs,
            recursiveFuncs: self.recursiveFuncs + other.recursiveFuncs,
            symmetrySets: self.symmetrySets + other.symmetrySets,
             symmetryGroups: self.symmetryGroups + other.symmetryGroups
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
            symmetrySets: self.symmetrySets,
            symmetryGroups: self.symmetryGroups
        )
    }
}

public protocol SpecComponent {}

public struct VarDecl: SpecComponent {
    public let name: String
    public let initial: TLAValue
    public let initialSet: StateExpr?
    public let initExpr: StateExpr?
    init(_ name: String, _ initial: TLAValue) { self.name = name; self.initial = initial; self.initialSet = nil; self.initExpr = nil }
    init(_ name: String, _ initial: TLAValue, initialSet: StateExpr?) { self.name = name; self.initial = initial; self.initialSet = initialSet; self.initExpr = nil }
    init(_ name: String, initExpr: StateExpr) { self.name = name; self.initial = .int(0); self.initialSet = nil; self.initExpr = initExpr }
}

public struct ActionDecl: SpecComponent {
    public let name: String
    public let body: ActionExpr
    init(_ name: String, _ body: ActionExpr) { self.name = name; self.body = body }
}

public struct InvDecl: SpecComponent {
    public let name: String
    public let body: StateExpr
    init(_ name: String, _ body: StateExpr) { self.name = name; self.body = body }
}

public struct TemporalDecl: SpecComponent {
    public let name: String
    public let expr: TemporalExpr
    init(_ name: String, _ expr: TemporalExpr) { self.name = name; self.expr = expr }
}

public struct FairnessDecl: SpecComponent {
    public let condition: FairnessCondition
    init(_ condition: FairnessCondition) { self.condition = condition }
}

public struct ConstantDecl: SpecComponent {
    public let name: String
    public let value: TLAValue
    init(_ name: String, _ value: TLAValue) { self.name = name; self.value = value }
}

public struct NamedValueDecl: Equatable, Sendable { public let name: String; public let value: TLAValue }

public struct OpDecl: SpecComponent {
    public let name: String; public let params: [String]; public let body: ActionExpr
    init(_ n: String, _ p: [String], _ b: ActionExpr) { name = n; params = p; body = b }
}
public func Operator(_ name: String, param: Var<some TLAValueType>, @ActionBuilder body: () -> ActionExpr) -> OpDecl {
    OpDecl(name, [param.name], body())
}

/// Spec registry for composition via UseSpec().
public enum SpecRegistry {
    nonisolated(unsafe) private static var store: [String: TLASpec] = [:]
    public static func register(_ spec: TLASpec) { store[spec.name] = spec }
    public static func lookup(_ name: String) -> TLASpec? { store[name] }
}

/// Compose a registered spec by name.  Parser handles this at compile time.
public struct UseSpecDecl: SpecComponent { public let name: String; init(_ n: String) { name = n } }
public func UseSpec(_ name: String) -> UseSpecDecl { UseSpecDecl(name) }

public struct OpUse: SpecComponent {
    public let op: String; public let param: String; public let varName: String; public let value: TLAValue?
    init(_ o: String, _ p: String, _ v: String, _ val: TLAValue? = nil) { op = o; param = p; varName = v; value = val }
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
    init(_ tlaText: String) { self.tlaText = tlaText; self.name = nil; self.body = nil }
    init(name: String, body: StateExpr) { self.tlaText = ""; self.name = name; self.body = body }
}

public struct TheoremDecl: SpecComponent, Equatable {
    public let tlaText: String
    public let name: String?
    public let temporalBody: TemporalExpr?
    public let stateBody: StateExpr?
    init(_ tlaText: String) { self.tlaText = tlaText; self.name = nil; self.temporalBody = nil; self.stateBody = nil }
    init(name: String, temporal: TemporalExpr) { self.tlaText = ""; self.name = name; self.temporalBody = temporal; self.stateBody = nil }
    init(name: String, state: StateExpr) { self.tlaText = ""; self.name = name; self.temporalBody = nil; self.stateBody = state }
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
        self.name = name; self.params = params; self.body = body
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
    public init(name: String, tlaBody: String, implementation: @escaping @Sendable ([TLAValue]) -> TLAValue) {
        self.name = name; self.tlaBody = tlaBody; self.implementation = implementation
    }
}

extension RuntimeFuncDecl: Equatable {
    public static func == (lhs: RuntimeFuncDecl, rhs: RuntimeFuncDecl) -> Bool {
        lhs.name == rhs.name && lhs.tlaBody == rhs.tlaBody
    }
}

@resultBuilder
public enum SpecBuilder {
    public static func buildBlock(_ components: [SpecComponent]...) -> [SpecComponent] { components.flatMap { $0 } }
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
    public static func buildExpression(_ expr: UseSpecDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: DeadlockDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: ConstraintDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: RecursiveDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: RecursiveFuncDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: RuntimeFuncDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: SymmetrySetDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: SymmetryVariableGroupDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: NamedValueDecl) -> [SpecComponent] { [] }
    public static func buildExpression(_ expr: OpDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: OpUse) -> [SpecComponent] { [expr] }
    public static func buildOptional(_ component: [SpecComponent]?) -> [SpecComponent] { component ?? [] }
    public static func buildEither(first: [SpecComponent]) -> [SpecComponent] { first }
    public static func buildEither(second: [SpecComponent]) -> [SpecComponent] { second }
    public static func buildArray(_ components: [[SpecComponent]]) -> [SpecComponent] { components.flatMap { $0 } }
}

/// Generate DSL elements for each value in a sequence.
/// `ForEach([pPhase1, pPhase2, pPhase3]) { p in Action(...) }`
public func ForEach<C: Sequence>(_ values: C, @SpecBuilder _ body: (C.Element) -> [SpecComponent]) -> [SpecComponent] {
    values.flatMap(body)
}

@resultBuilder
public enum InvariantBuilder {
    public static func buildBlock(_ components: StateExpr...) -> StateExpr {
        if components.isEmpty { return .value(.bool(true)) }
        return components.dropFirst().reduce(components[0]) { .and($0, $1) }
    }
    public static func buildExpression(_ expr: StateExpr) -> StateExpr { expr }
    public static func buildOptional(_ component: StateExpr?) -> StateExpr { component ?? .value(.bool(true)) }
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
    public static func buildOptional(_ component: ActionExpr?) -> ActionExpr { component ?? .guard_(.value(.bool(true))) }
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
public func Variable<T>(_ ref: Var<T>, _ initial: some TLAValueConvertible) -> VarDecl {
    VarDecl(ref.name, initial.tlaValue)
}

@discardableResult
public func Variable<T>(_ ref: Var<T>, in values: some Sequence<some TLAValueConvertible>) -> VarDecl {
    let set = Set(values.map(\.tlaValue))
    let stateSet: StateExpr = .setLiteral(set.map { .value($0) })
    return VarDecl(ref.name, .set(set), initialSet: stateSet)
}

// MARK: - Shared initial state computation

public func computeInitialStates(_ spec: TLASpec) -> [[String: TLAValue]] {
    let substituted = substituteConstants(spec)
    let base = Dictionary(uniqueKeysWithValues: substituted.variables.map { ($0.name, $0.initial) })
    let nondeterministic = substituted.variables.filter { v in
        guard v.initialSet != nil else { return false }
        if case .set = v.initial { return true }
        return false
    }
    var states: [[String: TLAValue]] = nondeterministic.reduce([base]) { states, variable in
        guard case .set(let values) = variable.initial else { return states }
        let sorted = TLAValue.sorted(values)
        return states.flatMap { state in sorted.map { state.merging([variable.name: $0]) { _, new in new } } }
    }
    for variable in substituted.variables where variable.initExpr != nil {
        states = states.compactMap { state in
            guard let val = try? variable.initExpr!.evaluate(in: state) else { return nil }
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
        let mapping: [TLAValue: TLAValue] = Dictionary(uniqueKeysWithValues:
            present.map { ($0, canonical) }
        )

        return state.mapValues { applyMapping($0, mapping) }
    }
}

private func valueContains(_ val: TLAValue, _ target: TLAValue) -> Bool {
    if val == target { return true }
    switch val {
    case .set(let s):
        return s.contains(where: { valueContains($0, target) })
    case .function(let f):
        for (k, v) in f {
            if valueContains(k, target) || valueContains(v, target) { return true }
        }
        return false
    case .tuple(let t):
        return t.contains(where: { valueContains($0, target) })
    case .record(let r):
        return r.values.contains(where: { valueContains($0, target) })
    default:
        return false
    }
}

private func stateContains(_ state: [String: TLAValue], _ target: TLAValue) -> Bool {
    state.values.contains(where: { valueContains($0, target) })
}

private func applyMapping(_ val: TLAValue, _ mapping: [TLAValue: TLAValue]) -> TLAValue {
    if let canonical = mapping[val] { return canonical }
    switch val {
    case .set(let s):
        return .set(Set(s.map { applyMapping($0, mapping) }))
    case .function(let f):
        var newFunc: [TLAValue: TLAValue] = [:]
        for (k, v) in f {
            let newKey = applyMapping(k, mapping)
            let newVal = applyMapping(v, mapping)
            newFunc[newKey] = newVal
        }
        return .function(newFunc)
    case .tuple(let elements):
        return .tuple(elements.map { applyMapping($0, mapping) })
    case .record(let fields):
        return .record(fields.mapValues { applyMapping($0, mapping) })
    default:
        return val
    }
}

public struct SymmetrySetDecl: SpecComponent {
    public let variableName: String
    public let values: Set<TLAValue>
    init(_ variableName: String, _ values: Set<TLAValue>) {
        self.variableName = variableName
        self.values = values
    }
}

public func Symmetry(_ variableName: String, _ values: Set<some TLAValueConvertible>) -> SymmetrySetDecl {
    SymmetrySetDecl(variableName, Set(values.map(\.tlaValue)))
}

public struct SymmetryVariableGroup: Hashable, Sendable { public let names: [String]; init(_ n: [String]) { names = n }
    func canonicalize(_ state: [String: TLAValue]) -> [String: TLAValue] {
        guard names.count > 1 else { return state }
        var vals = names.compactMap { state[$0] }
        guard vals.count == names.count else { return state }
        vals.sort(by: { $0.description < $1.description })
        var result = state
        for (i, name) in names.enumerated() { result[name] = vals[i] }
        return result
    }
}
public struct SymmetryVariableGroupDecl: SpecComponent { public let names: [String]; init(_ n: [String]) { names = n } }
public func SymmetryGroup(_ names: String...) -> SymmetryVariableGroupDecl { SymmetryVariableGroupDecl(names) }

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

public func DefineRecursive(_ name: String, params: [String], @InvariantBuilder body: () -> StateExpr) -> RecursiveFuncDecl {
    RecursiveFuncDecl(RecursiveFunc(name: name, params: params, body: body()))
}

public func RuntimeFunc(_ name: String, tlaBody: String, _ implementation: @escaping @Sendable ([TLAValue]) -> TLAValue) -> RuntimeFuncDecl {
    RuntimeFuncDecl(name: name, tlaBody: tlaBody, implementation: implementation)
}

extension TLASpec {
    public init(_ name: String, @SpecBuilder _ builder: () -> [SpecComponent]) {
        let components = builder()
        var variables: [NamedVar] = []
        var actions: [NamedAction] = []
        var invariants: [NamedInvariant] = []
        var temporalProperties: [NamedTemporal] = []
        var fairness: [FairnessCondition] = []
        var constants: [String: TLAValue] = [:]
        var definitions: [String] = []
        var theorems: [String] = []
        var assumes: StateExpr?
        var extendsMods = "Integers"
        var deadlockFlag = false
        var constraint: StateExpr?
        var recursiveDefs: [String] = []
        var recursiveFuncs: [RecursiveFunc] = []
        var useSpecs: [TLASpec] = []
        var runtimeFuncCollector: [String: @Sendable ([TLAValue]) -> TLAValue] = [:]
        var runtimeFuncBodiesCollector: [String] = []
        var symmetrySets: [SymmetrySet] = []
        var symmetryGroups: [SymmetryVariableGroup] = []
        var operators: [String: OpDecl] = [:]

        // Pass 1: collect operators
        for comp in components {
            if let op = comp as? OpDecl { operators[op.name] = op }
        }

        for comp in components {
            if let v = comp as? VarDecl { variables.append(NamedVar(name: v.name, initial: v.initial, initialSet: v.initialSet, initExpr: v.initExpr)) } else if let a = comp as? ActionDecl { actions.append(NamedAction(name: a.name, body: a.body)) } else if let i = comp as? InvDecl { invariants.append(NamedInvariant(name: i.name, body: i.body)) } else if let t = comp as? TemporalDecl { temporalProperties.append(NamedTemporal(name: t.name, expr: t.expr)) } else if let f = comp as? FairnessDecl { fairness.append(f.condition) } else if let c = comp as? ConstantDecl { constants[c.name] = c.value } else if let d = comp as? DefinitionDecl {
                if let name = d.name, let body = d.body {
                    definitions.append("\(name) == \(body)")
                } else {
                    definitions.append(d.tlaText)
                }
            } else if let th = comp as? TheoremDecl {
                if !th.tlaText.isEmpty {
                    theorems.append(th.tlaText)
                } else if let name = th.name, let body = th.temporalBody {
                    theorems.append("\(name) == Spec => \(body)")
                } else if let name = th.name, let body = th.stateBody {
                    theorems.append("\(name) == Spec => [](\(body))")
                }
            } else if let a = comp as? AssumeDecl { assumes = assumes.map { .and($0, a.expr) } ?? a.expr } else if let e = comp as? ExtendsDecl { extendsMods = e.modules } else if comp is DeadlockDecl { deadlockFlag = true } else if let c = comp as? ConstraintDecl { constraint = constraint.map { .and($0, c.body) } ?? c.body } else if let r = comp as? RecursiveDecl { recursiveDefs.append(r.tlaText) } else if let rf = comp as? RecursiveFuncDecl { recursiveFuncs.append(rf.funcDef) } else if let u = comp as? UseDecl { useSpecs.append(u.spec) } else if let rtf = comp as? RuntimeFuncDecl {
                runtimeFuncCollector[rtf.name] = rtf.implementation
                runtimeFuncBodiesCollector.append(rtf.tlaBody)
                runtimeFuncBodies.append(rtf.tlaBody)
            } else if let s = comp as? SymmetryVariableGroupDecl {
                symmetryGroups.append(SymmetryVariableGroup(s.names))
            } else if let s = comp as? SymmetrySetDecl {
                symmetrySets.append(SymmetrySet(variableName: s.variableName, values: s.values))
            } else if comp is OpDecl {
                // collected in pass 1
            } else if let u = comp as? UseSpecDecl {
                if let spec = SpecRegistry.lookup(u.name) {
                    variables += spec.variables
                    invariants += spec.invariants
                }
            } else if let u = comp as? OpUse {
                if let op = operators[u.op] {
                    let body: ActionExpr
                    let name: String
                    if let val = u.value {
                        body = substituteActionVar(op.params[0], with: val, in: op.body)
                        name = "\(u.op)_\(val)"
                    } else {
                        body = renameVar(op.params[0], to: u.varName, in: op.body)
                        name = "\(u.op)_\(u.varName)"
                    }
                    actions.append(NamedAction(name: name, body: body))
                }
            }
        }

        // Apply Use(spec) — compose used specs into this one
        for used in useSpecs {
            variables += used.variables
            actions += used.actions
            invariants += used.invariants
            constants.merge(used.constants) { $1 }
            definitions += used.definitions
            recursiveDefs += used.recursiveDefs
            recursiveFuncs += used.recursiveFuncs
            if let c = used.constraint { constraint = constraint.map { .and($0, c) } ?? c }
            if let a = used.assume { assumes = assumes.map { .and($0, a) } ?? a }
            symmetrySets += used.symmetrySets
        }

        // Auto-UNCHANGED: push into OR branches so TLC sees complete assignments
        let vn = variables.map(\.name)
        actions = actions.map { a in
            NamedAction(name: a.name, body: completeAction(a.body, allVars: vn))
        }

        self.name = name
        self.variables = variables
        self.constants = constants
        self.actions = actions
        self.invariants = invariants
        self.temporalProperties = temporalProperties
        self.fairness = fairness
        self.assume = assumes
        self.checkDeadlock = deadlockFlag
        self.definitions = definitions
        self.theorems = theorems
        self.extendsModules = extendsMods
        self.constraint = constraint
        self.recursiveDefs = recursiveDefs
        self.recursiveFuncs = recursiveFuncs
        self.runtimeFuncs = runtimeFuncCollector
        self.runtimeFuncBodies = runtimeFuncBodiesCollector
        self.symmetrySets = symmetrySets
        self.symmetryGroups = symmetryGroups
    }
}

public func substituteConstants(_ spec: TLASpec) -> TLASpec {
    let constants = spec.constants
    let vars = spec.variables.map { v in
        NamedVar(name: v.name, initial: substituteInValue(v.initial, constants: constants), initialSet: v.initialSet, initExpr: v.initExpr)
    }
    let acts = spec.actions.map { a in
        NamedAction(name: a.name, body: substituteInAction(a.body, constants: constants))
    }
    let invs = spec.invariants.map { i in
        NamedInvariant(name: i.name, body: substituteInState(i.body, constants: constants))
    }
    return TLASpec(
        name: spec.name,
        variables: vars,
        constants: [:],
        actions: acts,
        invariants: invs,
         temporalProperties: spec.temporalProperties.map { t in
            NamedTemporal(name: t.name, expr: substituteInTemporal(t.expr, constants: constants))
         },
        fairness: spec.fairness,
        assume: spec.assume.map { substituteInState($0, constants: constants) },
        checkDeadlock: spec.checkDeadlock,
        definitions: spec.definitions,
        theorems: spec.theorems,
        extendsModules: spec.extendsModules,
        constraint: spec.constraint.map { substituteInState($0, constants: constants) },
        recursiveDefs: spec.recursiveDefs,
        recursiveFuncs: spec.recursiveFuncs,
         symmetrySets: spec.symmetrySets,
         symmetryGroups: spec.symmetryGroups
    )
}

private func substituteActionVar(_ name: String, with value: TLAValue, in expr: ActionExpr) -> ActionExpr {
    switch expr {
    case .assign(let v, let e): return .assign(v, StateExpr.substituteVariable(name, value, in: e))
    case .unchanged: return expr
    case .guard_(let e): return .guard_(StateExpr.substituteVariable(name, value, in: e))
    case .chooseAction(let v, let s): return .chooseAction(v, StateExpr.substituteVariable(name, value, in: s))
    case .existsAction(let v, let s, let b): return .existsAction(v, StateExpr.substituteVariable(name, value, in: s), substituteActionVar(name, with: value, in: b))
    case .ifElse(let c, let t, let e): return .ifElse(StateExpr.substituteVariable(name, value, in: c), substituteActionVar(name, with: value, in: t), substituteActionVar(name, with: value, in: e))
    case .define(let v, let exp, let b): return .define(v, StateExpr.substituteVariable(name, value, in: exp), substituteActionVar(name, with: value, in: b))
    case .and(let a, let b): return .and(substituteActionVar(name, with: value, in: a), substituteActionVar(name, with: value, in: b))
    case .or(let a, let b): return .or(substituteActionVar(name, with: value, in: a), substituteActionVar(name, with: value, in: b))
    }
}

private func substituteInValue(_ value: TLAValue, constants: [String: TLAValue]) -> TLAValue {
    if case .constant(let name) = value, let replacement = constants[name] {
        return replacement
    }
    return value
}

private func substituteInState(_ expr: StateExpr, constants: [String: TLAValue]) -> StateExpr {
    switch expr {
    case .value(let v): return .value(substituteInValue(v, constants: constants))
    case .variable: return expr
    case .add(let a, let b): return .add(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .subtract(let a, let b): return .subtract(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .multiply(let a, let b): return .multiply(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .divide(let a, let b): return .divide(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .modulo(let a, let b): return .modulo(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .negate(let a): return .negate(substituteInState(a, constants: constants))
    case .integerDivide(let a, let b): return .integerDivide(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .equal(let a, let b): return .equal(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .notEqual(let a, let b): return .notEqual(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .lessThan(let a, let b): return .lessThan(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .lessOrEqual(let a, let b): return .lessOrEqual(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .greaterThan(let a, let b): return .greaterThan(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .greaterOrEqual(let a, let b): return .greaterOrEqual(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .and(let a, let b): return .and(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .or(let a, let b): return .or(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .not(let a): return .not(substituteInState(a, constants: constants))
    case .ifThenElse(let c, let t, let f): return .ifThenElse(substituteInState(c, constants: constants), substituteInState(t, constants: constants), substituteInState(f, constants: constants))
    case .setLiteral(let elems): return .setLiteral(elems.map { substituteInState($0, constants: constants) })
    case .in(let a, let b): return .in(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .subset(let a, let b): return .subset(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .union(let a, let b): return .union(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .intersection(let a, let b): return .intersection(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .setDifference(let a, let b): return .setDifference(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .cardinality(let a): return .cardinality(substituteInState(a, constants: constants))
    case .setFilter(let a, let qv, let b): return .setFilter(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
    case .setMap(let a, let qv, let b): return .setMap(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
    case .powerSet(let a): return .powerSet(substituteInState(a, constants: constants))
    case .unionAll(let a): return .unionAll(substituteInState(a, constants: constants))
    case .tupleLiteral(let elems): return .tupleLiteral(elems.map { substituteInState($0, constants: constants) })
    case .tupleAccess(let a, let i): return .tupleAccess(substituteInState(a, constants: constants), i)
    case .tupleLength(let a): return .tupleLength(substituteInState(a, constants: constants))
    case .tupleAppend(let a, let b): return .tupleAppend(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .tupleHead(let t): return .tupleHead(substituteInState(t, constants: constants))
    case .tupleTail(let t): return .tupleTail(substituteInState(t, constants: constants))
    case .tupleConcatenate(let a, let b): return .tupleConcatenate(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .recordLiteral(let fields): return .recordLiteral(fields.mapValues { substituteInState($0, constants: constants) })
    case .recordAccess(let a, let f): return .recordAccess(substituteInState(a, constants: constants), f)
    case .domain(let a): return .domain(substituteInState(a, constants: constants))
    case .functionLiteral(let a, let qv, let b): return .functionLiteral(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
    case .functionApply(let a, let b): return .functionApply(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .except(let a, let b, let c): return .except(substituteInState(a, constants: constants), substituteInState(b, constants: constants), substituteInState(c, constants: constants))
    case .caseExpr(let pairs, let other): return .caseExpr(pairs.map { substituteInState($0, constants: constants) }, other.map { substituteInState($0, constants: constants) })
    case .forAll(let a, let qv, let b): return .forAll(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
    case .exists(let a, let qv, let b): return .exists(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
     case .choose(let a, let qv, let b): return .choose(substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
     case .enabledAction: return expr
     case .sequenceFromSet(let s): return .sequenceFromSet(substituteInState(s, constants: constants))
     case .functionSet(let d, let r): return .functionSet(substituteInState(d, constants: constants), substituteInState(r, constants: constants))
     case .setSum(let f, let s): return .setSum(substituteInState(f, constants: constants), substituteInState(s, constants: constants))
     case .recursiveCall(let n, let a): return .recursiveCall(n, a.map { substituteInState($0, constants: constants) })
     }
}

private func substituteInAction(_ expr: ActionExpr, constants: [String: TLAValue]) -> ActionExpr {
    switch expr {
    case .assign(let v, let e): return .assign(v, substituteInState(e, constants: constants))
    case .unchanged: return expr
    case .guard_(let e): return .guard_(substituteInState(e, constants: constants))
    case .chooseAction(let v, let s): return .chooseAction(v, substituteInState(s, constants: constants))
    case .and(let a, let b): return .and(substituteInAction(a, constants: constants), substituteInAction(b, constants: constants))
    case .or(let a, let b): return .or(substituteInAction(a, constants: constants), substituteInAction(b, constants: constants))
    case .ifElse(let c, let t, let e): return .ifElse(substituteInState(c, constants: constants), substituteInAction(t, constants: constants), substituteInAction(e, constants: constants))
    case .define(let v, let exp, let body): return .define(v, substituteInState(exp, constants: constants), substituteInAction(body, constants: constants))
    case .existsAction(let v, let s, let b): return .existsAction(v, substituteInState(s, constants: constants), substituteInAction(b, constants: constants))
    }
}

public func assignedVars(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .assign(let v, _), .chooseAction(let v, _): return [v]
    case .unchanged, .guard_: return []
    case .and(let a, let b): return assignedVars(a).union(assignedVars(b))
    case .or(let a, let b): return assignedVars(a).union(assignedVars(b))
    case .ifElse(_, let t, let e): return assignedVars(t).union(assignedVars(e))
    case .define(_, _, let b): return assignedVars(b)
    case .existsAction(_, _, let b): return assignedVars(b)
    }
}

public func explicitUnchanged(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .unchanged(let v): return [v]
    case .and(let a, let b): return explicitUnchanged(a).union(explicitUnchanged(b))
    case .or(let a, let b): return explicitUnchanged(a).intersection(explicitUnchanged(b))
    case .ifElse: return []
    case .define: return []
    case .existsAction: return []
    default: return []
    }
}

/// Joint nondeterministic init: two variables from a constrained cross-product.
private func substituteInTemporal(_ expr: TemporalExpr, constants: [String: TLAValue]) -> TemporalExpr {
    switch expr {
    case .always(let s): return .always(substituteInState(s, constants: constants))
    case .eventually(let s): return .eventually(substituteInState(s, constants: constants))
    case .alwaysEventually(let s): return .alwaysEventually(substituteInState(s, constants: constants))
    case .eventuallyAlways(let s): return .eventuallyAlways(substituteInState(s, constants: constants))
    case .leadsTo(let a, let b): return .leadsTo(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    }
}

/// Deprecated — use two separate Variable() declarations with StateExpr constraints instead.
@available(*, deprecated, message: "Use two separate Variable() declarations")
public func Variable<T, U>(_ ref1: Var<T>, _ ref2: Var<U>, in range: ClosedRange<Int>, where predicate: (Int, Int) -> Bool) -> VarDecl {
    VarDecl("\(ref1.name)+\(ref2.name)", .tuple([]))
}

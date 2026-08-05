public struct NamedVar: Codable, Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let initial: TLAValue
    public let initialSet: StateExpr?
    public init(name: String, initial: TLAValue, initialSet: StateExpr? = nil) {
        self.name = name
        self.initial = initial
        self.initialSet = initialSet
    }
    public var description: String {
        if let s = initialSet { return "\(name) \\in \(s)" }
        return "\(name) = \(initial)"
    }
}

public struct NamedAction: Codable, Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let body: ActionExpr
    public init(name: String, body: ActionExpr) {
        self.name = name
        self.body = body
    }
    public var description: String { "\(name): \(body)" }
}

public struct NamedTemporal: Codable, Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let expr: TemporalExpr
    public init(name: String, expr: TemporalExpr) { self.name = name; self.expr = expr }
    public var description: String { "\(name): \(expr)" }
}

public struct NamedInvariant: Codable, Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let body: StateExpr
    public init(name: String, body: StateExpr) {
        self.name = name
        self.body = body
    }
    public var description: String { "\(name): \(body)" }
}

public struct TLASpec: Codable, Sendable, CustomStringConvertible, Equatable {
    public let name: String
    public let variables: [NamedVar]
    public let constants: [String: TLAValue]
    public let actions: [NamedAction]
    public let invariants: [NamedInvariant]
    public let temporalProperties: [NamedTemporal]
    public let fairness: [FairnessCondition]
    public let constraint: StateExpr?
    public let assume: StateExpr?
    public let checkDeadlock: Bool
    public let definitions: [String]
    public let theorems: [String]
    public let extendsModules: String

    public init(name: String, variables: [NamedVar], constants: [String: TLAValue] = [:], actions: [NamedAction], invariants: [NamedInvariant], temporalProperties: [NamedTemporal] = [], fairness: [FairnessCondition] = [], constraint: StateExpr? = nil, assume: StateExpr? = nil, checkDeadlock: Bool = false, definitions: [String] = [], theorems: [String] = [], extendsModules: String = "Integers") {
        self.name = name
        self.variables = variables
        self.constants = constants
        self.actions = actions
        self.invariants = invariants
        self.temporalProperties = temporalProperties
        self.fairness = fairness
        self.constraint = constraint
        self.assume = assume
        self.checkDeadlock = checkDeadlock
        self.definitions = definitions
        self.theorems = theorems
        self.extendsModules = extendsModules
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
        let prefixedName = prefix.map { "\($0)!\(self.name)" } ?? self.name
        let otherVars = other.variables.filter { v in !self.variables.contains(where: { $0.name == v.name }) }
        return TLASpec(
            name: prefixedName,
            variables: self.variables + otherVars,
            constants: self.constants.merging(other.constants) { $1 },
            actions: self.actions + other.actions,
            invariants: self.invariants + other.invariants,
            temporalProperties: self.temporalProperties + other.temporalProperties,
            fairness: self.fairness + other.fairness,
            constraint: self.constraint,
            assume: { if let a = self.assume, let b = other.assume { return .and(a, b) }; return self.assume ?? other.assume }(),
            checkDeadlock: self.checkDeadlock || other.checkDeadlock,
            definitions: self.definitions + other.definitions,
            theorems: self.theorems + other.theorems,
            extendsModules: self.extendsModules
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
            constraint: self.constraint,
            assume: self.assume,
            checkDeadlock: self.checkDeadlock,
            definitions: self.definitions,
            theorems: self.theorems,
            extendsModules: self.extendsModules
        )
    }
}

public protocol SpecComponent {}

public struct VarDecl: SpecComponent {
    public let name: String
    public let initial: TLAValue
    public let initialSet: StateExpr?
    public init(_ name: String, _ initial: TLAValue) { self.name = name; self.initial = initial; self.initialSet = nil }
    public init(_ name: String, _ initial: TLAValue, initialSet: StateExpr?) { self.name = name; self.initial = initial; self.initialSet = initialSet }
}

public struct ActionDecl: SpecComponent {
    public let name: String
    public let body: ActionExpr
    public init(_ name: String, _ body: ActionExpr) { self.name = name; self.body = body }
}

public struct InvDecl: SpecComponent {
    public let name: String
    public let body: StateExpr
    public init(_ name: String, _ body: StateExpr) { self.name = name; self.body = body }
}

public struct TemporalDecl: SpecComponent {
    public let name: String
    public let expr: TemporalExpr
    public init(_ name: String, _ expr: TemporalExpr) { self.name = name; self.expr = expr }
}

public struct FairnessDecl: SpecComponent {
    public let condition: FairnessCondition
    public init(_ condition: FairnessCondition) { self.condition = condition }
}

public struct ConstantDecl: SpecComponent {
    public let name: String
    public let value: TLAValue
    public init(_ name: String, _ value: TLAValue) { self.name = name; self.value = value }
}

public struct DefinitionDecl: SpecComponent, Equatable {
    public let tlaText: String
    public init(_ tlaText: String) { self.tlaText = tlaText }
}

public struct TheoremDecl: SpecComponent, Equatable {
    public let tlaText: String
    public let name: String?
    public let temporalBody: TemporalExpr?
    public let stateBody: StateExpr?
    public init(_ tlaText: String) { self.tlaText = tlaText; self.name = nil; self.temporalBody = nil; self.stateBody = nil }
    public init(name: String, temporal: TemporalExpr) { self.tlaText = ""; self.name = name; self.temporalBody = temporal; self.stateBody = nil }
    public init(name: String, state: StateExpr) { self.tlaText = ""; self.name = name; self.temporalBody = nil; self.stateBody = state }
}

public struct AssumeDecl: SpecComponent, Equatable {
    public let expr: StateExpr
    public init(_ expr: StateExpr) { self.expr = expr }
}

public struct ExtendsDecl: SpecComponent, Equatable {
    public let modules: String
    public init(_ modules: String) { self.modules = modules }
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
    public static func buildExpression(_ expr: DeadlockDecl) -> [SpecComponent] { [expr] }
    public static func buildOptional(_ component: [SpecComponent]?) -> [SpecComponent] { component ?? [] }
    public static func buildEither(first: [SpecComponent]) -> [SpecComponent] { first }
    public static func buildEither(second: [SpecComponent]) -> [SpecComponent] { second }
    public static func buildArray(_ components: [[SpecComponent]]) -> [SpecComponent] { components.flatMap { $0 } }
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
public func Variable<T>(_ ref: Var<T>, _ initial: some TLAValueConvertible) -> VarDecl {
    VarDecl(ref.name, initial.tlaValue)
}

@discardableResult
public func Variable<T>(_ ref: Var<T>, in values: some Sequence<some TLAValueConvertible>) -> VarDecl {
    let set = Set(values.map(\.tlaValue))
    let stateSet: StateExpr = .setLiteral(set.map { .value($0) })
    return VarDecl(ref.name, .set(set), initialSet: stateSet)
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

public struct DeadlockDecl: SpecComponent { public init() {} }
public func DeadlockCheck() -> DeadlockDecl { DeadlockDecl() }

public struct SymmetryDecl: SpecComponent {
    public let variableName: String
    public init(_ variableName: String) { self.variableName = variableName }
}

public func Symmetry(_ variableName: String) -> SymmetryDecl {
    SymmetryDecl(variableName)
}

public struct SymmetrySet: Hashable, Codable, Sendable, CustomStringConvertible {
    public let variableName: String
    public let values: Set<TLAValue>
    public init(variableName: String, values: Set<TLAValue>) {
        self.variableName = variableName
        self.values = values
    }
    public var description: String { "SYMMETRY \(variableName)" }

    func canonicalize(_ state: [String: TLAValue]) -> [String: TLAValue] {
        let sorted = values.sorted { $0.description < $1.description }
        let present = sorted.filter { value in
            state.values.contains(value)
        }
        guard !present.isEmpty else { return state }

        let mapping: [TLAValue: TLAValue] = Dictionary(uniqueKeysWithValues:
            zip(present, sorted.prefix(present.count))
        )

        return state.mapValues { val in
            if let canonical = mapping[val] { return canonical }
            if case .set(let s) = val {
                var newSet = Set<TLAValue>()
                for elem in s {
                    newSet.insert(mapping[elem] ?? elem)
                }
                return .set(newSet)
            }
            return val
        }
    }
}

public func Constant(_ name: String, _ value: some TLAValueConvertible) -> ConstantDecl {
    ConstantDecl(name, value.tlaValue)
}

public func Definition(_ tlaText: String) -> DefinitionDecl {
    DefinitionDecl(tlaText)
}

public func Theorem(_ tlaText: String) -> TheoremDecl {
    TheoremDecl(tlaText)
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

        for comp in components {
            if let v = comp as? VarDecl { variables.append(NamedVar(name: v.name, initial: v.initial, initialSet: v.initialSet)) }
            else if let a = comp as? ActionDecl { actions.append(NamedAction(name: a.name, body: a.body)) }
            else if let i = comp as? InvDecl { invariants.append(NamedInvariant(name: i.name, body: i.body)) }
            else if let t = comp as? TemporalDecl { temporalProperties.append(NamedTemporal(name: t.name, expr: t.expr)) }
            else if let f = comp as? FairnessDecl { fairness.append(f.condition) }
            else if let c = comp as? ConstantDecl { constants[c.name] = c.value }
            else if let d = comp as? DefinitionDecl { definitions.append(d.tlaText) }
            else if let th = comp as? TheoremDecl {
                if !th.tlaText.isEmpty {
                    theorems.append(th.tlaText)
                } else if let name = th.name, let body = th.temporalBody {
                    theorems.append("\(name) == Spec => \(body)")
                } else if let name = th.name, let body = th.stateBody {
                    theorems.append("\(name) == Spec => [](\(body))")
                }
            }
            else if let a = comp as? AssumeDecl { assumes = assumes.map { .and($0, a.expr) } ?? a.expr }
            else if let e = comp as? ExtendsDecl { extendsMods = e.modules }
            else if comp is DeadlockDecl { deadlockFlag = true }
        }

        // Auto-UNCHANGED: unassigned vars implicitly stay unchanged (like TLA+)
        let vn = variables.map(\.name)
        actions = actions.map { a in
            let assigned = assignedVars(a.body)
            let explicit = explicitUnchanged(a.body)
            var body = a.body
            for v in vn where !assigned.contains(v) && !explicit.contains(v) {
                body = .and(body, .unchanged(v))
            }
            return NamedAction(name: a.name, body: body)
        }

        self.name = name
        self.variables = variables
        self.constants = constants
        self.actions = actions
        self.invariants = invariants
        self.temporalProperties = temporalProperties
        self.fairness = fairness
        self.constraint = nil
        self.assume = assumes
        self.checkDeadlock = deadlockFlag
        self.definitions = definitions
        self.theorems = theorems
        self.extendsModules = extendsMods
    }
}

public func substituteConstants(_ spec: TLASpec) -> TLASpec {
    let constants = spec.constants
    let vars = spec.variables.map { v in
        NamedVar(name: v.name, initial: substituteInValue(v.initial, constants: constants))
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
        temporalProperties: spec.temporalProperties,
        fairness: spec.fairness,
        assume: spec.assume,
        checkDeadlock: spec.checkDeadlock,
        definitions: spec.definitions,
        theorems: spec.theorems,
        extendsModules: spec.extendsModules
    )
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
    case .setFilter(let a, let b): return .setFilter(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .setMap(let a, let b): return .setMap(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .powerSet(let a): return .powerSet(substituteInState(a, constants: constants))
    case .unionAll(let a): return .unionAll(substituteInState(a, constants: constants))
    case .tupleLiteral(let elems): return .tupleLiteral(elems.map { substituteInState($0, constants: constants) })
    case .tupleAccess(let a, let i): return .tupleAccess(substituteInState(a, constants: constants), i)
    case .tupleLength(let a): return .tupleLength(substituteInState(a, constants: constants))
    case .tupleAppend(let a, let b): return .tupleAppend(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .tupleConcatenate(let a, let b): return .tupleConcatenate(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .recordLiteral(let fields): return .recordLiteral(fields.mapValues { substituteInState($0, constants: constants) })
    case .recordAccess(let a, let f): return .recordAccess(substituteInState(a, constants: constants), f)
    case .domain(let a): return .domain(substituteInState(a, constants: constants))
    case .functionLiteral(let a, let b): return .functionLiteral(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .functionApply(let a, let b): return .functionApply(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .except(let a, let b, let c): return .except(substituteInState(a, constants: constants), substituteInState(b, constants: constants), substituteInState(c, constants: constants))
    case .caseExpr(let pairs, let other): return .caseExpr(pairs.map { substituteInState($0, constants: constants) }, other.map { substituteInState($0, constants: constants) })
    case .forAll(let a, let b): return .forAll(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .exists(let a, let b): return .exists(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .choose(let a, let b): return .choose(substituteInState(a, constants: constants), substituteInState(b, constants: constants))
    case .enabledAction: return expr
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
    }
}

private func assignedVars(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .assign(let v, _), .chooseAction(let v, _): return [v]
    case .unchanged, .guard_: return []
    case .and(let a, let b): return assignedVars(a).union(assignedVars(b))
    case .or(let a, let b): return assignedVars(a).union(assignedVars(b))
    }
}

private func explicitUnchanged(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .unchanged(let v): return [v]
    case .and(let a, let b): return explicitUnchanged(a).union(explicitUnchanged(b))
    case .or(let a, let b): return explicitUnchanged(a).intersection(explicitUnchanged(b))
    default: return []
    }
}

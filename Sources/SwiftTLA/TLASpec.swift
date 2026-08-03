public struct NamedVar: Codable, Sendable, CustomStringConvertible {
    public let name: String
    public let initial: TLAValue
    public init(name: String, initial: TLAValue) {
        self.name = name
        self.initial = initial
    }
    public var description: String { "\(name) = \(initial)" }
}

public struct NamedAction: Codable, Sendable, CustomStringConvertible {
    public let name: String
    public let body: ActionExpr
    public init(name: String, body: ActionExpr) {
        self.name = name
        self.body = body
    }
    public var description: String { "\(name): \(body)" }
}

public struct NamedTemporal: Codable, Sendable, CustomStringConvertible {
    public let name: String
    public let expr: TemporalExpr
    public init(name: String, expr: TemporalExpr) { self.name = name; self.expr = expr }
    public var description: String { "\(name): \(expr)" }
}

public struct NamedInvariant: Codable, Sendable, CustomStringConvertible {
    public let name: String
    public let body: StateExpr
    public init(name: String, body: StateExpr) {
        self.name = name
        self.body = body
    }
    public var description: String { "\(name): \(body)" }
}

public struct TLASpec: Codable, Sendable, CustomStringConvertible {
    public let name: String
    public let variables: [NamedVar]
    public let constants: [String: TLAValue]
    public let actions: [NamedAction]
    public let invariants: [NamedInvariant]
    public let temporalProperties: [NamedTemporal]
    public let fairness: [FairnessCondition]

    public init(name: String, variables: [NamedVar], constants: [String: TLAValue] = [:], actions: [NamedAction], invariants: [NamedInvariant], temporalProperties: [NamedTemporal] = [], fairness: [FairnessCondition] = []) {
        self.name = name
        self.variables = variables
        self.constants = constants
        self.actions = actions
        self.invariants = invariants
        self.temporalProperties = temporalProperties
        self.fairness = fairness
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

public struct VarDecl: SpecComponent {
    public let name: String
    public let initial: TLAValue
    public init(_ name: String, _ initial: TLAValue) { self.name = name; self.initial = initial }
}

public struct ActDecl: SpecComponent {
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

@resultBuilder
public enum SpecBuilder {
    public static func buildBlock(_ components: [SpecComponent]...) -> [SpecComponent] { components.flatMap { $0 } }
    public static func buildExpression(_ expr: VarDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: ActDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: InvDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: TemporalDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: FairnessDecl) -> [SpecComponent] { [expr] }
    public static func buildExpression(_ expr: ConstantDecl) -> [SpecComponent] { [expr] }
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

public func Variable<T>(_ ref: Var<T>, _ initial: some TLAValueConvertible) -> VarDecl {
    VarDecl(ref.name, initial.tlaValue)
}

public func Act(_ name: String, @ActionBuilder _ body: () -> ActionExpr) -> ActDecl {
    ActDecl(name, body())
}

public func Inv(_ name: String, @InvariantBuilder _ body: () -> StateExpr) -> InvDecl {
    InvDecl(name, body())
}

public func Temporal(_ name: String, _ expr: TemporalExpr) -> TemporalDecl {
    TemporalDecl(name, expr)
}

public func Fairness(_ condition: FairnessCondition) -> FairnessDecl {
    FairnessDecl(condition)
}

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

extension TLASpec {
    public init(_ name: String, @SpecBuilder _ builder: () -> [SpecComponent]) {
        let components = builder()
        var variables: [NamedVar] = []
        var actions: [NamedAction] = []
        var invariants: [NamedInvariant] = []
        var temporalProperties: [NamedTemporal] = []
        var fairness: [FairnessCondition] = []
        var constants: [String: TLAValue] = [:]

        for comp in components {
            if let v = comp as? VarDecl { variables.append(NamedVar(name: v.name, initial: v.initial)) }
            else if let a = comp as? ActDecl { actions.append(NamedAction(name: a.name, body: a.body)) }
            else if let i = comp as? InvDecl { invariants.append(NamedInvariant(name: i.name, body: i.body)) }
            else if let t = comp as? TemporalDecl { temporalProperties.append(NamedTemporal(name: t.name, expr: t.expr)) }
            else if let f = comp as? FairnessDecl { fairness.append(f.condition) }
            else if let c = comp as? ConstantDecl { constants[c.name] = c.value }
        }

        self.name = name
        self.variables = variables
        self.constants = constants
        self.actions = actions
        self.invariants = invariants
        self.temporalProperties = temporalProperties
        self.fairness = fairness
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
        fairness: spec.fairness
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

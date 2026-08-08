public protocol TLAValueType: TLAValueConvertible {
    static var defaultValue: Self { get }
}
extension Int: TLAValueType { public static var defaultValue: Int { 0 } }
extension Bool: TLAValueType { public static var defaultValue: Bool { false } }
extension String: TLAValueType { public static var defaultValue: String { "" } }

/// All RawRepresentable Int enums get TLAValueType support.
extension TLAValueType where Self: RawRepresentable, Self.RawValue == Int {
    public static var defaultValue: Self { Self(rawValue: 0)! }
    public var tlaValue: TLAValue { .int(rawValue) }
}

extension TLAValue: TLAValueType { public static var defaultValue: TLAValue { .int(0) } }

extension StateExprConvertible where Self: TLAValueType {
    public var stateExpr: StateExpr { .value(tlaValue) }
}
public enum TLASetType: TLAValueType { case placeholder; public var tlaValue: TLAValue { .set([]) }; public static var defaultValue: TLASetType { .placeholder } }
public enum TLATupleType: TLAValueType { case placeholder; public var tlaValue: TLAValue { .tuple([]) }; public static var defaultValue: TLATupleType { .placeholder } }
public enum TLARecordType: TLAValueType { case placeholder; public var tlaValue: TLAValue { .record([:]) }; public static var defaultValue: TLARecordType { .placeholder } }
public enum TLAFunctionType: TLAValueType { case placeholder; public var tlaValue: TLAValue { .function([:]) }; public static var defaultValue: TLAFunctionType { .placeholder } }
public typealias TLASet = TLASetType
public typealias TLATuple = TLATupleType
public typealias TLARecord = TLARecordType
public typealias TLASequence = TLATupleType  // TLA+ sequences are tuples at runtime

/// A typed TLA+ variable. Holds a name and typed initial value.
/// Used in `@TLAModel` spec bodies and builder DSL closures.
///
/// ```swift
/// let isLocked = Var<Bool>()              // name injected by @TLAModel macro
/// let isLocked = Var<Bool>(value: true)   // name injected, explicit initial
/// ```
/// Phantom-typed expression: `Expr<Int>` can only be assigned to `Var<Int>`.
public struct Expr<T: TLAValueType>: StateExprConvertible, Sendable {
    public let raw: StateExpr
    public init(_ raw: StateExpr) { self.raw = raw }
    public var stateExpr: StateExpr { raw }
}

@TypedVar
@dynamicMemberLookup
public struct Var<T: TLAValueType>: Sendable, CustomStringConvertible {
    public let name: String
    public init(_ name: String? = nil, value: T = T.defaultValue) {
        self.name = name ?? ""
    }
    public var description: String { name }
    /// Returns `x' = expression` — the variable's value in the next state.
    @discardableResult
    public func becomes(_ expression: some StateExprConvertible) -> ActionExpr { .assign(name, expression.stateExpr) }
    /// Type-safe assignment: `Var<Int>.becomes(5)` compiles, `Var<Int>.becomes("x")` does not.
    @discardableResult
    public func becomes(_ value: T) -> ActionExpr { .assign(name, .value(value.tlaValue)) }
    /// Returns `UNCHANGED x` — the variable stays the same in the next state.
    public var stays: ActionExpr { .unchanged(name) }

    public subscript(dynamicMember field: String) -> StateExpr {
        let v = StateExpr.variable(name)
        switch field {
        case "cardinality": return .cardinality(v)
        default: return .recordAccess(v, field)
        }
    }

    public var isEmpty: StateExpr { .equal(.cardinality(.variable(name)), .value(.int(0))) }
    public var cardinality: StateExpr { .cardinality(.variable(name)) }
}


/// Attaches a guard condition to an action.
/// `x.becomes(1).when(x == 0)` produces `(x == 0) /\ x' = 1`.
extension ActionExpr {
    @discardableResult
    public func when(_ condition: some StateExprConvertible) -> ActionExpr {
        .and(.guard_(condition.stateExpr), self)
    }
}

extension Dictionary where Key == String, Value == TLAValue {
    public subscript<T: TLAValueType>(_ variable: Var<T>) -> TLAValue? {
        get { self[variable.name] }
        set { self[variable.name] = newValue }
    }
}

public protocol StateExprConvertible { var stateExpr: StateExpr { get } }
extension StateExpr: StateExprConvertible { public var stateExpr: StateExpr { self } }
extension Int: StateExprConvertible { public var stateExpr: StateExpr { .value(.int(self)) } }
extension Bool: StateExprConvertible { public var stateExpr: StateExpr { .value(.bool(self)) } }
extension String: StateExprConvertible { public var stateExpr: StateExpr { .value(.string(self)) } }
extension Var: StateExprConvertible { public var stateExpr: StateExpr { .variable(name) } }
extension TLAValue: StateExprConvertible { public var stateExpr: StateExpr { .value(self) } }

// Forward all StateExpr methods through StateExprConvertible so that
// Var<TLASetType>.subtracting(...), Var<Int>.isIn(...), etc. work inside
// Action closures without explicit .stateExpr calls.
extension StateExprConvertible {
    public func isIn(_ set: some StateExprConvertible) -> StateExpr { stateExpr.isIn(set) }
    public func subtracting(_ other: some StateExprConvertible) -> StateExpr { stateExpr.subtracting(other) }
    public func isSubset(of other: some StateExprConvertible) -> StateExpr { stateExpr.isSubset(of: other) }
    public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible) -> StateExpr { stateExpr.updated(at: key, to: value) }
    public func applying(_ argument: some StateExprConvertible) -> StateExpr { stateExpr.applying(argument) }
    public var cardinality: StateExpr { stateExpr.cardinality }
    public var flattened: StateExpr { stateExpr.flattened }
    public var subsets: StateExpr { stateExpr.subsets }
    public var domain: StateExpr { stateExpr.domain }
    public var count: StateExpr { stateExpr.count }
    public func filtering(_ predicate: StateExpr) -> StateExpr { stateExpr.filtering(predicate) }
    public func mapping(_ expression: StateExpr) -> StateExpr { stateExpr.mapping(expression) }
    public func appending(_ element: StateExpr) -> StateExpr { stateExpr.appending(element) }
    public func concatenating(_ other: StateExpr) -> StateExpr { stateExpr.concatenating(other) }
    public var head: StateExpr { stateExpr.head }
    public var tail: StateExpr { stateExpr.tail }
    public func at(_ index: Int) -> StateExpr { stateExpr.at(index) }
    public func integerDivided(by divisor: some StateExprConvertible) -> StateExpr { stateExpr.integerDivided(by: divisor) }

    // `union` and `intersection` clash with StateExpr enum cases — call the constructor directly.
    public func union(_ other: some StateExprConvertible) -> StateExpr {
        StateExpr.union(stateExpr, other.stateExpr)
    }
    public func intersection(_ other: some StateExprConvertible) -> StateExpr {
        StateExpr.intersection(stateExpr, other.stateExpr)
    }
}

public protocol TLAValueConvertible { var tlaValue: TLAValue { get } }
extension TLAValue: TLAValueConvertible { public var tlaValue: TLAValue { self } }
extension Int: TLAValueConvertible { public var tlaValue: TLAValue { .int(self) } }
extension Bool: TLAValueConvertible { public var tlaValue: TLAValue { .bool(self) } }
extension String: TLAValueConvertible { public var tlaValue: TLAValue { .string(self) } }

// MARK: - Arithmetic (Var<Int> only)

extension Var where T == Int {
    public static func + <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .add(.variable(lhs.name), rhs.stateExpr) }
    public static func - <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .subtract(.variable(lhs.name), rhs.stateExpr) }
    public static func * <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .multiply(.variable(lhs.name), rhs.stateExpr) }
    public static func / <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .divide(.variable(lhs.name), rhs.stateExpr) }
    public static func % <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .modulo(.variable(lhs.name), rhs.stateExpr) }
}

// MARK: - Generic operators (StateExpr level)

extension StateExpr {
    public static func + <R: StateExprConvertible>(lhs: StateExpr, rhs: R) -> StateExpr { .add(lhs, rhs.stateExpr) }
    public static func - <R: StateExprConvertible>(lhs: StateExpr, rhs: R) -> StateExpr { .subtract(lhs, rhs.stateExpr) }
    public static func * <R: StateExprConvertible>(lhs: StateExpr, rhs: R) -> StateExpr { .multiply(lhs, rhs.stateExpr) }
    public static func / <R: StateExprConvertible>(lhs: StateExpr, rhs: R) -> StateExpr { .divide(lhs, rhs.stateExpr) }
    public static func % <R: StateExprConvertible>(lhs: StateExpr, rhs: R) -> StateExpr { .modulo(lhs, rhs.stateExpr) }
    public static func && (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .and(lhs, rhs) }
    public static func || (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .or(lhs, rhs) }
}

public func + <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .add(lhs.stateExpr, rhs.stateExpr) }
public func - <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .subtract(lhs.stateExpr, rhs.stateExpr) }
public func * <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .multiply(lhs.stateExpr, rhs.stateExpr) }
public func / <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .divide(lhs.stateExpr, rhs.stateExpr) }
public func % <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .modulo(lhs.stateExpr, rhs.stateExpr) }

public prefix func - <E: StateExprConvertible>(expression: E) -> StateExpr { .negate(expression.stateExpr) }
public prefix func ! <E: StateExprConvertible>(expression: E) -> StateExpr { .not(expression.stateExpr) }

// Generic == for StateExprConvertible types (Int, Bool, Var, etc.)
public func == <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }

// Shadow Equatable == for StateExpr → returns StateExpr not Bool
extension StateExpr {
    public static func == (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .equal(lhs, rhs) }
}
public func != <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .notEqual(lhs.stateExpr, rhs.stateExpr) }
public func <  <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .lessThan(lhs.stateExpr, rhs.stateExpr) }
public func <= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .lessOrEqual(lhs.stateExpr, rhs.stateExpr) }
public func >  <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .greaterThan(lhs.stateExpr, rhs.stateExpr) }
public func >= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .greaterOrEqual(lhs.stateExpr, rhs.stateExpr) }

public func && <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .and(lhs.stateExpr, rhs.stateExpr) }
public func || <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .or(lhs.stateExpr, rhs.stateExpr) }

extension StateExpr {
    public func isIn(_ set: some StateExprConvertible) -> StateExpr { .in(self, set.stateExpr) }
    public func union(_ other: some StateExprConvertible) -> StateExpr { .union(self, other.stateExpr) }
    public func intersection(_ other: some StateExprConvertible) -> StateExpr { .intersection(self, other.stateExpr) }
    public func subtracting(_ other: some StateExprConvertible) -> StateExpr { .setDifference(self, other.stateExpr) }
    public func isSubset(of other: some StateExprConvertible) -> StateExpr { .subset(self, other.stateExpr) }
    public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible) -> StateExpr { .except(self, key.stateExpr, value.stateExpr) }
    public func applying(_ argument: some StateExprConvertible) -> StateExpr { .functionApply(self, argument.stateExpr) }
    public var cardinality: StateExpr { .cardinality(self) }
    public var flattened: StateExpr { .unionAll(self) }
    public var subsets: StateExpr { .powerSet(self) }
    public var domain: StateExpr { .domain(self) }
    public var count: StateExpr { .tupleLength(self) }
    public var head: StateExpr { .tupleHead(self) }
    public var tail: StateExpr { .tupleTail(self) }
    public func filtering(_ predicate: StateExpr) -> StateExpr { .setFilter(self, .fresh(), predicate) }
    public func mapping(_ expression: StateExpr) -> StateExpr { .setMap(expression, .fresh(), self) }
    public func appending(_ element: StateExpr) -> StateExpr { .tupleAppend(self, element) }
    public func concatenating(_ other: StateExpr) -> StateExpr { .tupleConcatenate(self, other) }
    public func at(_ index: Int) -> StateExpr { .tupleAccess(self, index) }
    public func integerDivided(by divisor: some StateExprConvertible) -> StateExpr { .integerDivide(self, divisor.stateExpr) }

    public static func set(_ elements: [some StateExprConvertible]) -> StateExpr { .setLiteral(elements.map(\.stateExpr)) }
    public static func `for`(allIn set: StateExpr, _ predicate: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .forAll(set, qv, renameVar("x", to: qv.name, in: predicate))
    }
    public static func exists(in set: StateExpr, _ predicate: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .exists(set, qv, renameVar("x", to: qv.name, in: predicate))
    }
    public static func choose(from set: StateExpr, matching predicate: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .choose(set, qv, renameVar("x", to: qv.name, in: predicate))
    }
    public static func any(from set: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .choose(set, qv, .value(.bool(true)))
    }
    public static func function(domain: StateExpr, _ body: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .functionLiteral(domain, qv, renameVar("x", to: qv.name, in: body))
    }
    public static func tuple(_ elements: [some StateExprConvertible]) -> StateExpr { .tupleLiteral(elements.map(\.stateExpr)) }
    public static func record(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(fields) }
    public static func enabled(_ name: String) -> StateExpr { .enabledAction(name) }

    // MARK: - Var-based bound variables

    public static func forAll(_ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .forAll(set, qv, renameVar(variable.name, to: qv.name, in: body))
    }
    public static func exists(_ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .exists(set, qv, renameVar(variable.name, to: qv.name, in: body))
    }
    public static func choose(_ variable: Var<some TLAValueType>, from set: StateExpr, matching predicate: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .choose(set, qv, renameVar(variable.name, to: qv.name, in: predicate))
    }
    public static func functionLiteral(_ variable: Var<some TLAValueType>, in domain: StateExpr, _ body: StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .functionLiteral(domain, qv, renameVar(variable.name, to: qv.name, in: body))
    }

    // MARK: - Closure-based with InvariantBuilder context

    public static func forAll(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .forAll(set, qv, body(.variable(qv.name)))
    }
    public static func existsIn(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .exists(set, qv, body(.variable(qv.name)))
    }
    public static func filterSet(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        let qv = QuantVar.fresh()
        return .setFilter(set, qv, body(.variable(qv.name)))
    }
}

extension ActionExpr {
    public static func choose(_ variable: String, from set: StateExpr) -> ActionExpr { .chooseAction(variable, set) }

    public static func exists(_ name: String, from set: some StateExprConvertible,
                              _ body: (StateExpr) -> ActionExpr) -> ActionExpr {
        .existsAction(name, set.stateExpr, body(.variable(name)))
    }

    public static func ifElse(_ condition: some StateExprConvertible,
                               then: ActionExpr, else: ActionExpr) -> ActionExpr {
        .ifElse(condition.stateExpr, then, `else`)
    }

    public static func existsSubset(_ name: String, of set: some StateExprConvertible,
                                    _ body: (StateExpr) -> ActionExpr) -> ActionExpr {
        .existsAction(name, .powerSet(set.stateExpr), body(.variable(name)))
    }

    public static func define(_ name: String, as value: some StateExprConvertible,
                               in body: ActionExpr) -> ActionExpr {
        .define(name, value.stateExpr, body)
    }
}

extension StateExpr {
    /// Shorthand for single-element set: `.set(value)` = `setLiteral([value])`.
    public static func singleton(_ element: some StateExprConvertible) -> StateExpr {
        .setLiteral([element.stateExpr])
    }
}

/// Nondeterministically picks a value from a set and binds it to the variable.
/// `choose(s, from: q)` produces `s' ∈ q` (chooseAction). Subsequent references
/// to `s` in the action body resolve to the chosen value.
@discardableResult
public func choose(_ variable: Var<some TLAValueType>, from set: some StateExprConvertible) -> ActionExpr {
    .chooseAction(variable.name, set.stateExpr)
}

extension StateExpr {
    public static func `if`(_ condition: some StateExprConvertible, then: some StateExprConvertible, else: some StateExprConvertible) -> StateExpr {
        .ifThenElse(condition.stateExpr, then.stateExpr, `else`.stateExpr)
    }

    public static func firstMatch(
        _ cases: (when: StateExpr, then: StateExpr)...,
        fallback: StateExpr? = nil
    ) -> StateExpr {
        .caseExpr(cases.flatMap { [$0.when, $0.then] }, fallback)
    }
}

/// Replaces `.variable(from)` with `.variable(to)` throughout a StateExpr AST.
public func renameVar(_ from: String, to: String, in expr: StateExpr) -> StateExpr {
    switch expr {
    case .value, .enabledAction, .recursiveCall: return expr
    case .variable(let n): return .variable(n == from ? to : n)
    case .add(let a, let b): return .add(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .subtract(let a, let b): return .subtract(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .multiply(let a, let b): return .multiply(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .divide(let a, let b): return .divide(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .modulo(let a, let b): return .modulo(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .negate(let a): return .negate(renameVar(from, to: to, in: a))
    case .integerDivide(let a, let b): return .integerDivide(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .equal(let a, let b): return .equal(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .notEqual(let a, let b): return .notEqual(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .lessThan(let a, let b): return .lessThan(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .lessOrEqual(let a, let b): return .lessOrEqual(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .greaterThan(let a, let b): return .greaterThan(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .greaterOrEqual(let a, let b): return .greaterOrEqual(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .and(let a, let b): return .and(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .or(let a, let b): return .or(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .not(let a): return .not(renameVar(from, to: to, in: a))
    case .ifThenElse(let c, let t, let e): return .ifThenElse(renameVar(from, to: to, in: c), renameVar(from, to: to, in: t), renameVar(from, to: to, in: e))
    case .setLiteral(let es): return .setLiteral(es.map { renameVar(from, to: to, in: $0) })
    case .in(let e, let s): return .in(renameVar(from, to: to, in: e), renameVar(from, to: to, in: s))
    case .subset(let a, let b): return .subset(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .union(let a, let b): return .union(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .intersection(let a, let b): return .intersection(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .setDifference(let a, let b): return .setDifference(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .cardinality(let s): return .cardinality(renameVar(from, to: to, in: s))
    case .setFilter(let s, let qv, let p): return .setFilter(renameVar(from, to: to, in: s), qv, renameVar(from, to: to, in: p))
    case .setMap(let e, let qv, let s): return .setMap(renameVar(from, to: to, in: e), qv, renameVar(from, to: to, in: s))
    case .powerSet(let s): return .powerSet(renameVar(from, to: to, in: s))
    case .unionAll(let s): return .unionAll(renameVar(from, to: to, in: s))
    case .tupleLiteral(let es): return .tupleLiteral(es.map { renameVar(from, to: to, in: $0) })
    case .tupleAccess(let t, let i): return .tupleAccess(renameVar(from, to: to, in: t), i)
    case .tupleLength(let t): return .tupleLength(renameVar(from, to: to, in: t))
    case .tupleAppend(let t, let e): return .tupleAppend(renameVar(from, to: to, in: t), renameVar(from, to: to, in: e))
    case .tupleHead(let t): return .tupleHead(renameVar(from, to: to, in: t))
    case .tupleTail(let t): return .tupleTail(renameVar(from, to: to, in: t))
    case .tupleConcatenate(let a, let b): return .tupleConcatenate(renameVar(from, to: to, in: a), renameVar(from, to: to, in: b))
    case .recordLiteral(let fs): return .recordLiteral(fs.mapValues { renameVar(from, to: to, in: $0) })
    case .recordAccess(let r, let f): return .recordAccess(renameVar(from, to: to, in: r), f)
    case .domain(let f): return .domain(renameVar(from, to: to, in: f))
    case .functionLiteral(let d, let qv, let b): return .functionLiteral(renameVar(from, to: to, in: d), qv, renameVar(from, to: to, in: b))
    case .functionApply(let f, let x): return .functionApply(renameVar(from, to: to, in: f), renameVar(from, to: to, in: x))
    case .except(let f, let x, let e): return .except(renameVar(from, to: to, in: f), renameVar(from, to: to, in: x), renameVar(from, to: to, in: e))
    case .caseExpr(let ps, let fb): return .caseExpr(ps.map { renameVar(from, to: to, in: $0) }, fb.map { renameVar(from, to: to, in: $0) })
    case .forAll(let s, let qv, let p): return .forAll(renameVar(from, to: to, in: s), qv, renameVar(from, to: to, in: p))
    case .exists(let s, let qv, let p): return .exists(renameVar(from, to: to, in: s), qv, renameVar(from, to: to, in: p))
    case .choose(let s, let qv, let p): return .choose(renameVar(from, to: to, in: s), qv, renameVar(from, to: to, in: p))
    case .sequenceFromSet(let s): return .sequenceFromSet(renameVar(from, to: to, in: s))
    case .setSum(let f, let s): return .setSum(renameVar(from, to: to, in: f), renameVar(from, to: to, in: s))
    case .functionSet(let d, let r): return .functionSet(renameVar(from, to: to, in: d), renameVar(from, to: to, in: r))
    }
}

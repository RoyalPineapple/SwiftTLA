public protocol TLAValueType: TLAValueConvertible {
    static var defaultValue: Self { get }
}
extension Int: TLAValueType { public static var defaultValue: Int { 0 } }
extension Bool: TLAValueType { public static var defaultValue: Bool { false } }
extension String: TLAValueType { public static var defaultValue: String { "" } }
extension TLAValue: TLAValueType { public static var defaultValue: TLAValue { .int(0) } }
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
/// let isLocked = Var(0)          // Var<Int>, name inferred from binding
/// let isLocked = Var("isLocked") // explicit name
/// ```
@dynamicMemberLookup
public struct Var<T: TLAValueType>: Sendable, CustomStringConvertible {
    public let name: String
    public init(_ name: String? = nil, value: T? = nil) {
        self.name = name ?? ""
    }
    public var description: String { name }
    /// Returns `x' = expression` — the variable's value in the next state.
    @discardableResult
    public func becomes(_ expression: some StateExprConvertible) -> ActionExpr { .assign(name, expression.stateExpr) }
    /// Returns `UNCHANGED x` — the variable stays the same in the next state.
    public var stays: ActionExpr { .unchanged(name) }

    public subscript(dynamicMember field: String) -> StateExpr { .recordAccess(.variable(name), field) }
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
    public func filtering(_ predicate: StateExpr) -> StateExpr { .setFilter(self, predicate) }
    public func mapping(_ expression: StateExpr) -> StateExpr { .setMap(expression, self) }
    public func appending(_ element: StateExpr) -> StateExpr { .tupleAppend(self, element) }
    public func concatenating(_ other: StateExpr) -> StateExpr { .tupleConcatenate(self, other) }
    public func at(_ index: Int) -> StateExpr { .tupleAccess(self, index) }
    public func integerDivided(by divisor: some StateExprConvertible) -> StateExpr { .integerDivide(self, divisor.stateExpr) }

    public static func set(_ elements: [some StateExprConvertible]) -> StateExpr { .setLiteral(elements.map(\.stateExpr)) }
    public static func `for`(allIn set: StateExpr, _ predicate: StateExpr) -> StateExpr { .forAll(set, predicate) }
    public static func exists(in set: StateExpr, _ predicate: StateExpr) -> StateExpr { .exists(set, predicate) }
    public static func choose(from set: StateExpr, matching predicate: StateExpr) -> StateExpr { .choose(set, predicate) }
    public static func any(from set: StateExpr) -> StateExpr { .choose(set, .value(.bool(true))) }
    public static func function(domain: StateExpr, _ body: StateExpr) -> StateExpr { .functionLiteral(domain, body) }
    public static func tuple(_ elements: [some StateExprConvertible]) -> StateExpr { .tupleLiteral(elements.map(\.stateExpr)) }
    public static func record(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(fields) }
    public static func enabled(_ name: String) -> StateExpr { .enabledAction(name) }

    // MARK: - Var-based bound variables

    public static func forAll(_ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr) -> StateExpr {
        .forAll(set, substituteVariableBody(variable.name, with: "_x", in: body))
    }
    public static func exists(_ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr) -> StateExpr {
        .exists(set, substituteVariableBody(variable.name, with: "_x", in: body))
    }
    public static func choose(_ variable: Var<some TLAValueType>, from set: StateExpr, matching predicate: StateExpr) -> StateExpr {
        .choose(set, substituteVariableBody(variable.name, with: "_x", in: predicate))
    }
    public static func functionLiteral(_ variable: Var<some TLAValueType>, in domain: StateExpr, _ body: StateExpr) -> StateExpr {
        .functionLiteral(domain, substituteVariableBody(variable.name, with: "_x", in: body))
    }

    // MARK: - Closure-based with InvariantBuilder context

    public static func forAll(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        .forAll(set, body(.variable("_x")))
    }
    public static func existsIn(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        .exists(set, body(.variable("_x")))
    }
    public static func filterSet(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr) -> StateExpr {
        .setFilter(set, body(.variable("_x")))
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

/// Replaces `.variable(from)` with `.variable(to)` throughout a StateExpr.
/// Used to bind user-facing variable names to the internal `_x` placeholder
/// so the evaluator's `substituteVariable("_x", value, ...)` can bind actual values.
public func substituteVariableBody(_ from: String, with to: String, in expression: StateExpr) -> StateExpr {
    replaceVarInState(from, with: to, in: expression)
}

private func replaceVarInState(_ from: String, with to: String, in expression: StateExpr) -> StateExpr {
    switch expression {
    case .variable(let name): return name == from ? .variable(to) : expression
    case .value, .enabledAction: return expression
    case .add(let l, let r): return .add(replace(l), replace(r))
    case .subtract(let l, let r): return .subtract(replace(l), replace(r))
    case .multiply(let l, let r): return .multiply(replace(l), replace(r))
    case .divide(let l, let r): return .divide(replace(l), replace(r))
    case .modulo(let l, let r): return .modulo(replace(l), replace(r))
    case .negate(let x): return .negate(replace(x))
    case .integerDivide(let l, let r): return .integerDivide(replace(l), replace(r))
    case .equal(let l, let r): return .equal(replace(l), replace(r))
    case .notEqual(let l, let r): return .notEqual(replace(l), replace(r))
    case .lessThan(let l, let r): return .lessThan(replace(l), replace(r))
    case .lessOrEqual(let l, let r): return .lessOrEqual(replace(l), replace(r))
    case .greaterThan(let l, let r): return .greaterThan(replace(l), replace(r))
    case .greaterOrEqual(let l, let r): return .greaterOrEqual(replace(l), replace(r))
    case .and(let l, let r): return .and(replace(l), replace(r))
    case .or(let l, let r): return .or(replace(l), replace(r))
    case .not(let x): return .not(replace(x))
    case .ifThenElse(let c, let t, let e): return .ifThenElse(replace(c), replace(t), replace(e))
    case .setLiteral(let es): return .setLiteral(es.map(replace))
    case .in(let e, let s): return .in(replace(e), replace(s))
    case .subset(let a, let b): return .subset(replace(a), replace(b))
    case .union(let a, let b): return .union(replace(a), replace(b))
    case .intersection(let a, let b): return .intersection(replace(a), replace(b))
    case .setDifference(let a, let b): return .setDifference(replace(a), replace(b))
    case .cardinality(let s): return .cardinality(replace(s))
    case .setFilter(let s, let p): return .setFilter(replace(s), replace(p))
    case .setMap(let e, let s): return .setMap(replace(e), replace(s))
    case .powerSet(let s): return .powerSet(replace(s))
    case .unionAll(let s): return .unionAll(replace(s))
    case .tupleLiteral(let es): return .tupleLiteral(es.map(replace))
    case .tupleAccess(let t, let i): return .tupleAccess(replace(t), i)
    case .tupleLength(let t): return .tupleLength(replace(t))
    case .tupleAppend(let t, let e): return .tupleAppend(replace(t), replace(e))
    case .tupleHead(let t): return .tupleHead(replace(t))
        case .tupleTail(let t): return .tupleTail(replace(t))
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(replace(a), replace(b))
    case .recordLiteral(let fs): return .recordLiteral(fs.mapValues(replace))
    case .recordAccess(let r, let f): return .recordAccess(replace(r), f)
    case .domain(let f): return .domain(replace(f))
    case .functionLiteral(let d, let body): return .functionLiteral(replace(d), replace(body))
    case .functionApply(let f, let x): return .functionApply(replace(f), replace(x))
    case .except(let f, let x, let e): return .except(replace(f), replace(x), replace(e))
    case .caseExpr(let ps, let fb): return .caseExpr(ps.map(replace), fb.map(replace))
    case .forAll(let s, let p): return .forAll(replace(s), replace(p))
    case .exists(let s, let p): return .exists(replace(s), replace(p))
    case .choose(let s, let p): return .choose(replace(s), replace(p))
    case .sequenceFromSet(let s): return .sequenceFromSet(replace(s))
    case .setSum(let f, let s): return .setSum(replace(f), replace(s))
    case .recursiveCall(let n, let a): return .recursiveCall(n, a.map(replace))
    }

    func replace(_ expr: StateExpr) -> StateExpr { replaceVarInState(from, with: to, in: expr) }
}

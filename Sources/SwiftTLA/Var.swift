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
public typealias TLASet = TLASetType
public typealias TLATuple = TLATupleType
public typealias TLARecord = TLARecordType

/// A typed TLA+ variable. Holds a name and typed initial value.
/// Used in `@TLAModel` spec bodies and builder DSL closures.
///
/// ```swift
/// let isLocked = Var(0)          // Var<Int>, name inferred from binding
/// let isLocked = Var("isLocked") // explicit name
/// ```
@dynamicMemberLookup
public struct Var<T: TLAValueType>: Codable, Sendable, CustomStringConvertible {
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

public func == <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
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
}

extension ActionExpr {
    public static func choose(_ variable: String, from set: StateExpr) -> ActionExpr { .chooseAction(variable, set) }
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

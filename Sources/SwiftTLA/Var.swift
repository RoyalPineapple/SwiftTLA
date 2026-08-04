public protocol TLAValueType: TLAValueConvertible {}
extension Int: TLAValueType {}
extension Bool: TLAValueType {}
public enum TLASetType: TLAValueType { public var tlaValue: TLAValue { .set([]) } }
public enum TLATupleType: TLAValueType { public var tlaValue: TLAValue { .tuple([]) } }
public enum TLARecordType: TLAValueType { public var tlaValue: TLAValue { .record([:]) } }
public typealias TLASet = TLASetType
public typealias TLATuple = TLATupleType
public typealias TLARecord = TLARecordType

public struct Var<T: TLAValueType>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(_ name: String, _ value: T) { self.name = name }
    public init(_ value: T) { self.name = "" }
    public var description: String { name }
    @_spi(Internal) public var prime: PrimedVar<T> { PrimedVar(name: name) }
    public func becomes(_ expr: some StateExprConvertible) -> ActionExpr { .assign(name, expr.stateExpr) }
    public static func stays(_ v: Var) -> ActionExpr { .unchanged(v.name) }
    public var stays: ActionExpr { .unchanged(name) }
}

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

@_spi(Internal) public struct PrimedVar<T: TLAValueType>: Sendable { public let name: String }
@_spi(Internal) public func prime<T>(_ v: Var<T>) -> PrimedVar<T> { PrimedVar(name: v.name) }

public protocol StateExprConvertible { var stateExpr: StateExpr { get } }
extension StateExpr: StateExprConvertible { public var stateExpr: StateExpr { self } }
extension Int: StateExprConvertible { public var stateExpr: StateExpr { .value(.int(self)) } }
extension Bool: StateExprConvertible { public var stateExpr: StateExpr { .value(.bool(self)) } }
extension Var: StateExprConvertible { public var stateExpr: StateExpr { .variable(name) } }

public protocol TLAValueConvertible { var tlaValue: TLAValue { get } }
extension TLAValue: TLAValueConvertible { public var tlaValue: TLAValue { self } }
extension Int: TLAValueConvertible { public var tlaValue: TLAValue { .int(self) } }
extension Bool: TLAValueConvertible { public var tlaValue: TLAValue { .bool(self) } }

// MARK: - Arithmetic (Var<Int> only)

extension Var where T == Int {
    public static func + <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .add(.variable(lhs.name), rhs.stateExpr) }
    public static func - <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .subtract(.variable(lhs.name), rhs.stateExpr) }
    public static func * <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .multiply(.variable(lhs.name), rhs.stateExpr) }
    public static func / <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .divide(.variable(lhs.name), rhs.stateExpr) }
    public static func % <R: StateExprConvertible>(lhs: Var, rhs: R) -> StateExpr { .modulo(.variable(lhs.name), rhs.stateExpr) }
}

extension TLAExprShim where T == Int {
    public static func + <R: StateExprConvertible>(lhs: TLAExprShim, rhs: R) -> StateExpr { .add(lhs.stateExpr, rhs.stateExpr) }
}

// MARK: - TLAExpr helpers (for StateExpr-level ops)

public struct TLAExprShim<T: TLAValueType>: StateExprConvertible {
    public let stateExpr: StateExpr
    public init(_ e: StateExpr) { self.stateExpr = e }
}

// MARK: - Generic StateExpr operators via protocol

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

public prefix func - <E: StateExprConvertible>(expr: E) -> StateExpr { .negate(expr.stateExpr) }
public prefix func ! (expr: StateExpr) -> StateExpr { .not(expr) }

// MARK: - Comparisons (any Var or StateExprConvertible)

public func == <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
public func != <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .notEqual(lhs.stateExpr, rhs.stateExpr) }
public func <  <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .lessThan(lhs.stateExpr, rhs.stateExpr) }
public func <= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .lessOrEqual(lhs.stateExpr, rhs.stateExpr) }
public func >  <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .greaterThan(lhs.stateExpr, rhs.stateExpr) }
public func >= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .greaterOrEqual(lhs.stateExpr, rhs.stateExpr) }

// MARK: - Primed assignments

@_spi(Internal) public func == <T: TLAValueType, R: StateExprConvertible>(lhs: PrimedVar<T>, rhs: R) -> ActionExpr { .assign(lhs.name, rhs.stateExpr) }
@_spi(Internal) public func == <T: TLAValueType>(lhs: PrimedVar<T>, rhs: Var<T>) -> ActionExpr { .assign(lhs.name, .variable(rhs.name)) }

// MARK: - Set operators as domain notation

infix operator ∈ : ComparisonPrecedence
infix operator ⊆ : ComparisonPrecedence
infix operator ∪ : AdditionPrecedence
infix operator ∩ : MultiplicationPrecedence

public func ∈ <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .in(lhs.stateExpr, rhs.stateExpr) }
public func ⊆ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .subset(lhs, rhs) }
public func ∪ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .union(lhs, rhs) }
public func ∩ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .intersection(lhs, rhs) }

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

    public static func set(_ elements: [some StateExprConvertible]) -> StateExpr { .setLiteral(elements.map(\.stateExpr)) }
    public static func `for`(allIn set: StateExpr, _ predicate: StateExpr) -> StateExpr { .forAll(set, predicate) }
    public static func exists(in set: StateExpr, _ predicate: StateExpr) -> StateExpr { .exists(set, predicate) }
    public static func choose(from set: StateExpr, matching predicate: StateExpr) -> StateExpr { .choose(set, predicate) }
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
}

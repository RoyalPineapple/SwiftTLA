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
    public init(_ name: String, _: T.Type = T.self) { self.name = name }
    public var description: String { name }
}

public struct PrimedVar<T: TLAValueType>: Sendable { public let name: String }
public func next<T>(_ v: Var<T>) -> PrimedVar<T> { PrimedVar(name: v.name) }

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

public func == <T: TLAValueType, R: StateExprConvertible>(lhs: PrimedVar<T>, rhs: R) -> ActionExpr { .assign(lhs.name, rhs.stateExpr) }
public func == <T: TLAValueType>(lhs: PrimedVar<T>, rhs: Var<T>) -> ActionExpr { .assign(lhs.name, .variable(rhs.name)) }

// MARK: - Set operators

public func setExpr(_ elements: [some StateExprConvertible]) -> StateExpr { .setLiteral(elements.map(\.stateExpr)) }
public func cardinality(_ e: some StateExprConvertible) -> StateExpr { .cardinality(e.stateExpr) }
public func setDifference(_ a: StateExpr, _ b: StateExpr) -> StateExpr { .setDifference(a, b) }
public func powerSet(_ e: some StateExprConvertible) -> StateExpr { .powerSet(e.stateExpr) }
public func unionAll(_ e: some StateExprConvertible) -> StateExpr { .unionAll(e.stateExpr) }
public func domain(_ e: some StateExprConvertible) -> StateExpr { .domain(e.stateExpr) }
public func functionLiteral(domain: StateExpr, _ body: StateExpr) -> StateExpr { .functionLiteral(domain, body) }
public func functionApply(_ f: StateExpr, _ x: StateExpr) -> StateExpr { .functionApply(f, x) }
public func setFilter(_ s: StateExpr, _ p: StateExpr) -> StateExpr { .setFilter(s, p) }
public func setMap(_ e: StateExpr, over s: StateExpr) -> StateExpr { .setMap(e, s) }
public func tupleExpr(_ elements: [some StateExprConvertible]) -> StateExpr { .tupleLiteral(elements.map(\.stateExpr)) }
public func recordExpr(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(fields) }
public func tupleLength(_ e: some StateExprConvertible) -> StateExpr { .tupleLength(e.stateExpr) }
public func tupleAppend(_ t: StateExpr, _ e: StateExpr) -> StateExpr { .tupleAppend(t, e) }
public func tupleConcatenate(_ a: StateExpr, _ b: StateExpr) -> StateExpr { .tupleConcatenate(a, b) }
public func integerDivide(_ a: StateExpr, _ b: StateExpr) -> StateExpr { .integerDivide(a, b) }
public func forAll(_ set: StateExpr, _ predicate: StateExpr) -> StateExpr { .forAll(set, predicate) }
public func exists(_ set: StateExpr, _ predicate: StateExpr) -> StateExpr { .exists(set, predicate) }
public func choose(_ set: StateExpr, _ predicate: StateExpr) -> StateExpr { .choose(set, predicate) }
public func enabled(_ actionName: String) -> StateExpr { .enabledAction(actionName) }

infix operator ∈ : ComparisonPrecedence
infix operator ⊆ : ComparisonPrecedence
infix operator ∪ : AdditionPrecedence
infix operator ∩ : MultiplicationPrecedence

public func ∈ <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .in(lhs.stateExpr, rhs.stateExpr) }
public func ⊆ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .subset(lhs, rhs) }
public func ∪ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .union(lhs, rhs) }
public func ∩ (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .intersection(lhs, rhs) }

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

/// All RawRepresentable String enums get TLAValueType support.
extension TLAValueType where Self: RawRepresentable, Self.RawValue == String {
    public static var defaultValue: Self { Self(rawValue: "")! }
    public var tlaValue: TLAValue { .string(rawValue) }
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
import SwiftSyntaxMacros

// MARK: - VarConstraint

public enum VarConstraint: Hashable, Sendable {
    case intRange(ClosedRange<Int>)
    case enumValues([String])

    public func tlaExpr(for name: String) -> StateExpr {
        let v = StateExpr.variable(name)
        switch self {
        case .intRange(let r):
            return (v >= r.lowerBound) && (v <= r.upperBound)
        case .enumValues(let vals):
            return StateExpr.in(v, .setLiteral(vals.map { .value(.string($0)) }))
        }
    }

    public func check(_ value: TLAValue) -> Bool {
        switch self {
        case .intRange(let r): if case .int(let v) = value { return r.contains(v) }; return false
        case .enumValues(let vals): if case .string(let s) = value { return vals.contains(s) }; return false
        }
    }
}

// MARK: - Expr<T>

/// Phantom-typed expression: `Expr<Int>` can only be assigned to `Var<Int>`.
public struct Expr<T: TLAValueType>: StateExprConvertible, Sendable {
    public let raw: StateExpr
    public init(_ raw: StateExpr) { self.raw = raw }
    public var stateExpr: StateExpr { raw }
}

@dynamicMemberLookup
public struct Var<T: TLAValueType>: Sendable, CustomStringConvertible, SpecComponent {
    public let name: String
    public let initial: TLAValue?
    public let constraint: VarConstraint?

    public init(_ name: String, _ value: T) {
        self.name = name
        self.initial = value.tlaValue
        self.constraint = nil
    }
    public init(_ name: String? = nil, _ initial: TLAValue? = nil, constraint: VarConstraint? = nil) {
        self.name = name ?? ""
        self.initial = initial
        self.constraint = constraint
    }
    public init(_ name: String? = nil, bounded range: ClosedRange<Int>) where T == Int {
        self.name = name ?? ""
        self.initial = nil
        self.constraint = .intRange(range)
    }
    public init(_ name: String? = nil, values: [String]) where T == String {
        self.name = name ?? ""
        self.initial = nil
        self.constraint = .enumValues(values)
    }
    public var description: String { name }
    /// Type-safe assignment: `Var<Int>.becomes(5)` — only values matching T.
    @discardableResult
    public func becomes(_ value: T) -> ActionExpr { .assign(name, .value(value.tlaValue)) }
    /// Type-safe assignment: `Var<Int>.becomes(x + 1)` — only Expr<T>.
    @discardableResult
    public func becomes(_ expr: Expr<T>) -> ActionExpr { .assign(name, expr.raw) }
    /// Assign the value of another Var: `y0.becomes(x1)`.
    @discardableResult
    public func becomes(_ other: Var<T>) -> ActionExpr { .assign(name, other.stateExpr) }
    /// Legacy: untyped StateExpr assignment.
    @discardableResult
    public func becomes(_ expr: some StateExprConvertible) -> ActionExpr { .assign(name, expr.stateExpr) }
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

// MARK: - ArrayVar<T>

/// A lightweight Typed TLA+ variable wrapping a tuple (sequence).
/// Domain = 0..<count.
///
/// ```swift
/// let vals = ArrayVar<Int>("vals", count: 3)
/// vals[0]                // StateExpr: vals[1]
/// vals.becomes([1,2,3])  // vals' = <<1,2,3>>
/// ```
public struct ArrayVar<T: TLAValueType>: Sendable, CustomStringConvertible {
    public let name: String
    public let count: Int

    public init(_ name: String? = nil, count: Int) {
        self.name = name ?? ""
        self.count = count
    }

    public var description: String { name }

    public subscript(index: Int) -> StateExpr {
        .tupleAccess(.variable(name), index)
    }

    @discardableResult
    public func becomes(_ values: [T]) -> ActionExpr {
        .assign(name, .tupleLiteral(values.map { .value($0.tlaValue) }))
    }

    @discardableResult
    public func becomes(_ expr: some StateExprConvertible) -> ActionExpr {
        .assign(name, expr.stateExpr)
    }

    @discardableResult
    public func becomes(_ other: ArrayVar<T>) -> ActionExpr {
        .assign(name, other.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(name) }
}

extension ArrayVar: StateExprConvertible {
    public var stateExpr: StateExpr { .variable(name) }
}

// MARK: - Layer 2: ArrayVar native operations

extension ArrayVar {
    @discardableResult
    public func append(_ element: T) -> ActionExpr {
        .assign(name, .tupleAppend(.variable(name), StateExpr.value(element.tlaValue)))
    }

    public var sizeExpr: StateExpr {
        .tupleLength(.variable(name))
    }

    public var isEmptyExpr: StateExpr {
        .equal(.tupleLength(.variable(name)), StateExpr.value(.int(0)))
    }

    public func extract(from state: [String: TLAValue]) -> [T] where T: TLABridgeable {
        guard case .tuple(let t) = state[name] else { return [] }
        return t.map { T(tlaValue: $0) }
    }

    public func update(in state: inout [String: TLAValue], to newValue: [T]) where T: TLABridgeable {
        state[name] = .tuple(newValue.map { $0.tlaValue })
    }
}

// MARK: - DictMember<K>

/// Opaque member token for DictionaryVar.
public struct DictMember<K: Identifiable>: Sendable {
    public let key: TLAValue
    public init(key: TLAValue) { self.key = key }
}

// MARK: - DictionaryVar<K, V>

/// A lightweight TLA+ dictionary wrapping a function. Symmetry proven.
///
/// ```swift
/// let dict = DictionaryVar<DeviceID, Bool>("enabled", scope: 4)
/// dict[member]               // Expr<Bool>: enabled[memKey]
/// dict.update(member, to: true)  // enabled' = [enabled EXCEPT ![memKey] = TRUE]
/// dict.allSatisfy { $0 == true } // ∀ m ∈ DOMAIN enabled: enabled[m] = TRUE
/// ```
public struct DictionaryVar<K: Identifiable, V: TLAValueType>: Sendable, CustomStringConvertible {
    public let name: String
    public let scope: Int

    public init(_ name: String? = nil, scope: Int = 4) {
        self.name = name ?? ""
        self.scope = scope
    }

    public var description: String { name }

    public subscript(member: DictMember<K>) -> Expr<V> {
        Expr(.functionApply(.variable(name), .value(member.key)))
    }

    @discardableResult
    public func update(_ member: DictMember<K>, to value: V) -> ActionExpr {
        update(member, to: Expr<V>(.value(value.tlaValue)))
    }

    @discardableResult
    public func update(_ member: DictMember<K>, to value: Expr<V>) -> ActionExpr {
        .assign(name, .except(.variable(name), .value(member.key), value.raw))
    }

    public func allSatisfy(_ predicate: (Expr<V>) -> StateExpr) -> StateExpr {
        let mv = QuantVar.fresh()
        let value = Expr<V>(.functionApply(.variable(name), .variable(mv.name)))
        return .forAll(.domain(.variable(name)), mv, predicate(value))
    }

    public func contains(where predicate: (Expr<V>) -> StateExpr) -> StateExpr {
        let mv = QuantVar.fresh()
        let value = Expr<V>(.functionApply(.variable(name), .variable(mv.name)))
        return .exists(.domain(.variable(name)), mv, predicate(value))
    }
}

extension DictionaryVar: StateExprConvertible {
    public var stateExpr: StateExpr { .variable(name) }
}

// MARK: - Layer 2: DictionaryVar native operations

extension DictionaryVar {
    public func contains(key: K) -> StateExpr where K: TLAValueConvertible {
        .in(StateExpr.value(key.tlaValue), .domain(.variable(name)))
    }

    public var isEmptyExpr: StateExpr {
        .equal(.cardinality(.domain(.variable(name))), StateExpr.value(.int(0)))
    }

    public func extract(from state: [String: TLAValue]) -> [K: V] where K: TLABridgeable & Hashable, V: TLABridgeable {
        guard case .function(let f) = state[name] else { return [:] }
        var result: [K: V] = [:]
        for (k, v) in f {
            result[K(tlaValue: k)] = V(tlaValue: v)
        }
        return result
    }

    public func update(in state: inout [String: TLAValue], to newValue: [K: V]) where K: TLABridgeable & Hashable, V: TLABridgeable {
        let mapped: [TLAValue: TLAValue] = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.tlaValue, $0.value.tlaValue) })
        state[name] = .function(mapped)
    }
}

// MARK: - SetVar<T>

/// A lightweight TLA+ variable wrapping a set.
///
/// ```swift
/// let s = SetVar<Int>("seen")
/// s.becomes([1,2,3])   // seen' = {1, 2, 3}
/// ```
public struct SetVar<T: TLAValueType>: Sendable, CustomStringConvertible {
    public let name: String

    public init(_ name: String? = nil) {
        self.name = name ?? ""
    }

    public var description: String { name }

    @discardableResult
    public func becomes(_ elements: [T]) -> ActionExpr {
        .assign(name, .setLiteral(elements.map { .value($0.tlaValue) }))
    }

    @discardableResult
    public func becomes(_ expr: some StateExprConvertible) -> ActionExpr {
        .assign(name, expr.stateExpr)
    }

    @discardableResult
    public func becomes(_ other: SetVar<T>) -> ActionExpr {
        .assign(name, other.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(name) }
}

extension SetVar: StateExprConvertible {
    public var stateExpr: StateExpr { .variable(name) }
}

// MARK: - Layer 2: SetVar native operations

extension SetVar {
    @discardableResult
    public func insert(_ element: T) -> ActionExpr {
        .assign(name, .union(.variable(name), StateExpr.singleton(StateExpr.value(element.tlaValue))))
    }

    @discardableResult
    public func remove(_ element: T) -> ActionExpr {
        .assign(name, .setDifference(.variable(name), StateExpr.singleton(StateExpr.value(element.tlaValue))))
    }

    public func contains(_ element: T) -> StateExpr {
        .in(StateExpr.value(element.tlaValue), .variable(name))
    }

    public var isEmpty: StateExpr {
        .equal(.cardinality(.variable(name)), StateExpr.value(.int(0)))
    }

    @discardableResult
    public func union(_ other: some StateExprConvertible) -> ActionExpr {
        .assign(name, .union(.variable(name), other.stateExpr))
    }

    public func extract(from state: [String: TLAValue]) -> Set<T> where T: TLABridgeable & Hashable {
        guard case .set(let s) = state[name] else { return [] }
        return Set(s.map { T(tlaValue: $0) })
    }

    public func update(in state: inout [String: TLAValue], to newValue: Set<T>) where T: TLABridgeable & Hashable {
        state[name] = .set(Set(newValue.map { $0.tlaValue }))
    }
}

// MARK: - Builder integration

extension SpecBuilder {
    public static func buildExpression<T: TLAValueType>(_ expr: ArrayVar<T>) -> [SpecComponent] {
        let initial = TLAValue.tuple(Array(repeating: T.defaultValue.tlaValue, count: expr.count))
        return [VarDecl(expr.name, initial, collectionType: .array(expr.count))]
    }

    public static func buildExpression<K: Identifiable, V: TLAValueType>(_ expr: DictionaryVar<K, V>) -> [SpecComponent] {
        if expr.scope > 0 {
            return [SymmetricCollectionDecl(name: expr.name, verificationScope: expr.scope, initial: V.defaultValue.tlaValue)]
        }
        return [VarDecl(expr.name, .function([:]), collectionType: .dictionary(expr.scope))]
    }

    public static func buildExpression<T: TLAValueType>(_ expr: SetVar<T>) -> [SpecComponent] {
        [VarDecl(expr.name, .set([]), collectionType: .set)]
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

// MARK: - TLABridgeable protocol

public protocol TLABridgeable {
    var tlaValue: TLAValue { get }
    init(tlaValue: TLAValue)
}

extension Bool: TLABridgeable {
    public init(tlaValue: TLAValue) {
        if case .bool(let v) = tlaValue { self = v } else { self = false }
    }
}

extension Int: TLABridgeable {
    public init(tlaValue: TLAValue) {
        if case .int(let v) = tlaValue { self = v } else { self = 0 }
    }
}

extension String: TLABridgeable {
    public init(tlaValue: TLAValue) {
        if case .string(let v) = tlaValue { self = v } else { self = "" }
    }
}

extension Array: TLABridgeable where Element: TLABridgeable {
    public init(tlaValue: TLAValue) {
        if case .tuple(let elements) = tlaValue {
            self = elements.map { Element.init(tlaValue: $0) }
        } else {
            self = []
        }
    }
    public var tlaValue: TLAValue {
        .tuple(self.map { $0.tlaValue })
    }
}

extension Set: TLABridgeable where Element: TLABridgeable & Hashable {
    public init(tlaValue: TLAValue) {
        if case .set(let elements) = tlaValue {
            self = Set(elements.compactMap { Element.init(tlaValue: $0) })
        } else {
            self = []
        }
    }
    public var tlaValue: TLAValue {
        var mapped = Set<TLAValue>()
        for elem in self { mapped.insert(elem.tlaValue) }
        return .set(mapped)
    }
}

// MARK: - Arithmetic (Var<Int> only)

// MARK: - Generic operators (StateExprConvertible level)

public func + <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .add(lhs.stateExpr, rhs.stateExpr) }
public func - <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .subtract(lhs.stateExpr, rhs.stateExpr) }
public func * <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .multiply(lhs.stateExpr, rhs.stateExpr) }
public func / <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .divide(lhs.stateExpr, rhs.stateExpr) }
public func % <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .modulo(lhs.stateExpr, rhs.stateExpr) }

// MARK: - StateExpr-level operators (for direct StateExpr use)

extension StateExpr {
    public static func - (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .subtract(lhs, rhs) }
    public static func * (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .multiply(lhs, rhs) }
    public static func / (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .divide(lhs, rhs) }
    public static func % (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .modulo(lhs, rhs) }
    public static func && (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .and(lhs, rhs) }
    public static func || (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .or(lhs, rhs) }
}

public prefix func - <E: StateExprConvertible>(expression: E) -> StateExpr { .negate(expression.stateExpr) }
public prefix func ! <E: StateExprConvertible>(expression: E) -> StateExpr { .not(expression.stateExpr) }

public func == <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
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

/// A typed TLA+ variable. Holds a name and typed initial value.
/// Used in `@TLAModel` spec bodies and builder DSL closures.
///
/// ```swift
/// let isLocked = Var<Bool>()              // name injected by @TLAModel macro
/// let isLocked = Var<Bool>(value: true)   // name injected, explicit initial
/// ```
import SwiftSyntaxMacros

public protocol TLAValueType: TLAValueConvertible, StateExprConvertible, Sendable {
  static var defaultValue: Self { get }
  init?(formalValue: TLAValue)
}
extension Int: TLAValueType {
  public static var defaultValue: Int { 0 }
  public init?(formalValue: TLAValue) {
    guard case .int(let value) = formalValue else { return nil }
    self = value
  }
}
extension Bool: TLAValueType {
  public static var defaultValue: Bool { false }
  public init?(formalValue: TLAValue) {
    guard case .bool(let value) = formalValue else { return nil }
    self = value
  }
}
extension String: TLAValueType {
  public static var defaultValue: String { "" }
  public init?(formalValue: TLAValue) {
    guard case .string(let value) = formalValue else { return nil }
    self = value
  }
}

extension TLAValueType where Self: RawRepresentable, Self.RawValue == Int {
  public init?(formalValue: TLAValue) {
    guard case .int(let value) = formalValue else { return nil }
    self.init(rawValue: value)
  }
}

extension TLAValueType
where Self: RawRepresentable, Self.RawValue == Int, Self: CustomStringConvertible {
  public var tlaValue: TLAValue { .string(description) }
  public var description: String { String(describing: self) }
}

extension TLAValueType where Self: RawRepresentable, Self.RawValue == String {
  public init?(formalValue: TLAValue) {
    guard case .string(let value) = formalValue else { return nil }
    self.init(rawValue: value)
  }
}

extension TLAValue: TLAValueType {
  public static var defaultValue: TLAValue { .int(0) }
  public init?(formalValue: TLAValue) { self = formalValue }
}

extension TLARecord: TLAValueType {
  public static var defaultValue: TLARecord { TLARecord([]) }
  public init?(formalValue: TLAValue) {
    guard case .record(let value) = formalValue else { return nil }
    self = value
  }
  public var tlaValue: TLAValue { .record(self) }
}

extension StateExprConvertible where Self: TLAValueType {
  public var stateExpr: StateExpr { .value(tlaValue) }
}

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
    case .intRange(let r):
      if case .int(let v) = value { return r.contains(v) }
      return false
    case .enumValues(let vals):
      if case .string(let s) = value { return vals.contains(s) }
      return false
    }
  }
}

// MARK: - Expr<T>

/// Phantom-typed expression: `Expr<Int>` can only be assigned to `Var<Int>`.
public struct Expr<T: TLAValueType>: StateExprConvertible, Sendable {
  public let raw: StateExpr
  public init(_ raw: StateExpr) { self.raw = raw }
  public init(_ value: T) { raw = value.sourceIssue.map(StateExpr.sourceIssue) ?? .value(value.tlaValue) }
  public var stateExpr: StateExpr { raw }

  /// Typed equality keeps enum literals contextual in formal expressions:
  /// `car[Car.door] == .closed`.
  public static func == (lhs: Expr<T>, rhs: T) -> StateExpr {
    .equal(lhs.raw, .value(rhs.tlaValue))
  }

  public static func == (lhs: T, rhs: Expr<T>) -> StateExpr {
    .equal(.value(lhs.tlaValue), rhs.raw)
  }

  public static func != (lhs: Expr<T>, rhs: T) -> StateExpr {
    .notEqual(lhs.raw, .value(rhs.tlaValue))
  }

  public static func != (lhs: T, rhs: Expr<T>) -> StateExpr {
    .notEqual(.value(lhs.tlaValue), rhs.raw)
  }
}

public struct Var<T: TLAValueType>: Sendable, CustomStringConvertible, SpecComponent {
  public let name: String
  public let initial: TLAValue?
  public let constraint: VarConstraint?
  public let sourceIssue: SourceModelIssue?

  public init(_ name: String, _ value: T) {
    self.name = name
    self.initial = value.tlaValue
    self.constraint = nil
    self.sourceIssue = value.sourceIssue
  }
  public init(_ name: String? = nil, _ initial: TLAValue? = nil, constraint: VarConstraint? = nil) {
    self.name = name ?? ""
    self.initial = initial
    self.constraint = constraint
    self.sourceIssue = nil
  }
  public init(_ name: String? = nil, bounded range: ClosedRange<Int>) where T == Int {
    self.name = name ?? ""
    self.initial = nil
    self.constraint = .intRange(range)
    self.sourceIssue = nil
  }
  public init(_ name: String? = nil, values: [String]) where T == String {
    self.name = name ?? ""
    self.initial = nil
    self.constraint = .enumValues(values)
    self.sourceIssue = nil
  }
  public var description: String { name }
  /// Type-safe assignment: `Var<Int>.becomes(5)` — only values matching T.
  @discardableResult
  public func becomes(_ value: T) -> ActionExpr { .assign(.named(name), .value(value.tlaValue)) }
  /// Type-safe assignment: `Var<Int>.becomes(x + 1)` — only Expr<T>.
  @discardableResult
  public func becomes(_ expr: Expr<T>) -> ActionExpr { .assign(.named(name), expr.raw) }
  /// Assign the value of another Var: `y0.becomes(x1)`.
  @discardableResult
  public func becomes(_ other: Var<T>) -> ActionExpr { .assign(.named(name), other.stateExpr) }
  /// Returns `UNCHANGED x` — the variable stays the same in the next state.
  public var stays: ActionExpr { .unchanged(.named(name)) }

}

/// Attaches a guard condition to an action.
/// `x.becomes(1).when(x == 0)` produces `(x == 0) /\ x' = 1`.
extension ActionExpr {
  @discardableResult
  public func when(_ condition: some StateExprConvertible) -> ActionExpr {
    .and(.guard_(condition.stateExpr), self)
  }
}

public protocol StateExprConvertible { var stateExpr: StateExpr { get } }
extension StateExpr: StateExprConvertible { public var stateExpr: StateExpr { self } }
extension Int: StateExprConvertible { public var stateExpr: StateExpr { .value(.int(self)) } }
extension Bool: StateExprConvertible { public var stateExpr: StateExpr { .value(.bool(self)) } }
extension String: StateExprConvertible { public var stateExpr: StateExpr { .value(.string(self)) } }
extension Var: StateExprConvertible { public var stateExpr: StateExpr { .variable(name) } }
extension TLAValue: StateExprConvertible { public var stateExpr: StateExpr { .value(self) } }

public protocol TLAValueConvertible {
  var tlaValue: TLAValue { get }
  var sourceIssue: SourceModelIssue? { get }
}

extension TLAValueConvertible {
  public var sourceIssue: SourceModelIssue? { nil }
}

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

public func + <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .add(lhs.stateExpr, rhs.stateExpr)
}
public func - <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .subtract(lhs.stateExpr, rhs.stateExpr)
}
public func * <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .multiply(lhs.stateExpr, rhs.stateExpr)
}
public func / <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .divide(lhs.stateExpr, rhs.stateExpr)
}
public func % <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .modulo(lhs.stateExpr, rhs.stateExpr)
}

// MARK: - StateExpr-level operators (for direct StateExpr use)

extension StateExpr {
  public static func - (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .subtract(lhs, rhs) }
  public static func * (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .multiply(lhs, rhs) }
  public static func / (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .divide(lhs, rhs) }
  public static func % (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .modulo(lhs, rhs) }
  public static func && (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .and(lhs, rhs) }
  public static func || (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .or(lhs, rhs) }
}

public prefix func - <E: StateExprConvertible>(expression: E) -> StateExpr {
  .negate(expression.stateExpr)
}
public prefix func ! <E: StateExprConvertible>(expression: E) -> StateExpr {
  .not(expression.stateExpr)
}

public func == <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .equal(lhs.stateExpr, rhs.stateExpr)
}

extension StateExpr {
  public static func == (lhs: StateExpr, rhs: StateExpr) -> StateExpr { .equal(lhs, rhs) }
}
public func != <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .notEqual(lhs.stateExpr, rhs.stateExpr)
}

public func < <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .lessThan(lhs.stateExpr, rhs.stateExpr)
}
public func <= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .lessOrEqual(lhs.stateExpr, rhs.stateExpr)
}
public func > <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .greaterThan(lhs.stateExpr, rhs.stateExpr)
}
public func >= <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .greaterOrEqual(lhs.stateExpr, rhs.stateExpr)
}

public func && <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .and(lhs.stateExpr, rhs.stateExpr)
}
public func || <L: StateExprConvertible, R: StateExprConvertible>(lhs: L, rhs: R) -> StateExpr {
  .or(lhs.stateExpr, rhs.stateExpr)
}

extension StateExpr {
  public func isIn(_ set: some StateExprConvertible) -> StateExpr { .in(self, set.stateExpr) }
  public func union(_ other: some StateExprConvertible) -> StateExpr {
    .union(self, other.stateExpr)
  }
  public func intersection(_ other: some StateExprConvertible) -> StateExpr {
    .intersection(self, other.stateExpr)
  }
  public func subtracting(_ other: some StateExprConvertible) -> StateExpr {
    .setDifference(self, other.stateExpr)
  }
  public func isSubset(of other: some StateExprConvertible) -> StateExpr {
    .subset(self, other.stateExpr)
  }
  public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible)
    -> StateExpr { .except(self, key.stateExpr, value.stateExpr) }
  public func applying(_ argument: some StateExprConvertible) -> StateExpr {
    .functionApply(self, argument.stateExpr)
  }
  public var cardinality: StateExpr { .cardinality(self) }
  public var flattened: StateExpr { .unionAll(self) }
  public var subsets: StateExpr { .powerSet(self) }
  public var domain: StateExpr { .domain(self) }
  public var count: StateExpr { .tupleLength(self) }
  public var head: StateExpr { .tupleHead(self) }
  public var tail: StateExpr { .tupleTail(self) }
  public func filtering(_ predicate: StateExpr) -> StateExpr {
    .setFilter(self, generatedBinderName(), predicate)
  }
  public func mapping(_ expression: StateExpr) -> StateExpr {
    .setMap(expression, generatedBinderName(), self)
  }
  public func appending(_ element: StateExpr) -> StateExpr { .tupleAppend(self, element) }
  public func concatenating(_ other: StateExpr) -> StateExpr { .tupleConcatenate(self, other) }
  public func at(_ index: Int) -> StateExpr { .tupleAccess(self, index) }
  public func integerDivided(by divisor: some StateExprConvertible) -> StateExpr {
    .integerDivide(self, divisor.stateExpr)
  }

  public static func set(_ elements: [some StateExprConvertible]) -> StateExpr {
    .setLiteral(elements.map(\.stateExpr))
  }
  public static func `for`(allIn set: StateExpr, _ predicate: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .forAll(set, qv, renameVar("x", to: qv, in: predicate))
  }
  public static func exists(in set: StateExpr, _ predicate: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .exists(set, qv, renameVar("x", to: qv, in: predicate))
  }
  public static func choose(from set: StateExpr, matching predicate: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .choose(set, qv, renameVar("x", to: qv, in: predicate))
  }
  public static func any(from set: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .choose(set, qv, .value(.bool(true)))
  }
  public static func function(domain: StateExpr, _ body: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .functionLiteral(domain, qv, renameVar("x", to: qv, in: body))
  }
  public static func tuple(_ elements: [some StateExprConvertible]) -> StateExpr {
    .tupleLiteral(elements.map(\.stateExpr))
  }
  public static func record(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(.init(fields)) }
  public static func enabled(_ name: String) -> StateExpr { .enabledAction(name) }

  // MARK: - Var-based bound variables

  public static func forAll(
    _ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    let qv = generatedBinderName()
    return .forAll(set, qv, renameVar(variable.name, to: qv, in: body))
  }
  public static func exists(
    _ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    let qv = generatedBinderName()
    return .exists(set, qv, renameVar(variable.name, to: qv, in: body))
  }
  public static func choose(
    _ variable: Var<some TLAValueType>, from set: StateExpr, matching predicate: StateExpr
  ) -> StateExpr {
    let qv = generatedBinderName()
    return .choose(set, qv, renameVar(variable.name, to: qv, in: predicate))
  }
  public static func functionLiteral(
    _ variable: Var<some TLAValueType>, in domain: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    let qv = generatedBinderName()
    return .functionLiteral(domain, qv, renameVar(variable.name, to: qv, in: body))
  }

  // MARK: - Closure-based with InvariantBuilder context

  public static func forAll(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr)
    -> StateExpr {
    let qv = generatedBinderName()
    return .forAll(set, qv, body(.variable(qv)))
  }
  public static func existsIn(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr)
    -> StateExpr {
    let qv = generatedBinderName()
    return .exists(set, qv, body(.variable(qv)))
  }
  public static func filterSet(_ set: StateExpr, @InvariantBuilder _ body: (StateExpr) -> StateExpr)
    -> StateExpr {
    let qv = generatedBinderName()
    return .setFilter(set, qv, body(.variable(qv)))
  }
}

extension ActionExpr {
  public static func choose(_ variable: String, from set: StateExpr) -> ActionExpr {
    .chooseAction(.named(variable), set)
  }

  public static func exists(
    _ name: String, from set: some StateExprConvertible,
    _ body: (StateExpr) -> ActionExpr
  ) -> ActionExpr {
    .existsAction(name, set.stateExpr, body(.variable(name)))
  }

  public static func ifElse(
    _ condition: some StateExprConvertible,
    then: ActionExpr, else: ActionExpr
  ) -> ActionExpr {
    .ifElse(condition.stateExpr, then, `else`)
  }

  public static func existsSubset(
    _ name: String, of set: some StateExprConvertible,
    _ body: (StateExpr) -> ActionExpr
  ) -> ActionExpr {
    .existsAction(name, .powerSet(set.stateExpr), body(.variable(name)))
  }

  public static func define(
    _ name: String, as value: some StateExprConvertible,
    in body: ActionExpr
  ) -> ActionExpr {
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
public func choose(_ variable: Var<some TLAValueType>, from set: some StateExprConvertible)
  -> ActionExpr {
  .chooseAction(.named(variable.name), set.stateExpr)
}

extension StateExpr {
  public static func `if`(
    _ condition: some StateExprConvertible, then: some StateExprConvertible,
    else: some StateExprConvertible
  ) -> StateExpr {
    .ifThenElse(condition.stateExpr, then.stateExpr, `else`.stateExpr)
  }

  public static func firstMatch(
    _ cases: (when: StateExpr, then: StateExpr)...,
    fallback: StateExpr? = nil
  ) -> StateExpr {
    .caseExpr(cases.flatMap { [$0.when, $0.then] }, fallback)
  }
}

package func renameVar(_ from: String, to: String, in expr: StateExpr) -> StateExpr {
  StateExpr.substituteVariable(from, with: .variable(to), in: expr)
}

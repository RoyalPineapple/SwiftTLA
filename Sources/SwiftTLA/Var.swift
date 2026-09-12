/// A modeled value is also a constant typed expression of itself.
public protocol TLAValueType: TLAValueConvertible, TypedExpression, Sendable where ExpressionValue == Self {
  static var defaultValue: Self { get }
  static var formalValueShape: FormalValueShape { get }
  init?(formalValue: TLAValue)
}
extension TLAValueType {
  public var expr: Expr<Self> { Expr(self) }
  public var stateExpr: StateExpr { expr.stateExpr }
  public static var formalValueShape: FormalValueShape { .unsupported(String(reflecting: Self.self)) }
}

extension Int: TLAValueType {
  public static var formalValueShape: FormalValueShape { .integer }
  public static var defaultValue: Int { 0 }
  public init?(formalValue: TLAValue) {
    guard case .int(let value) = formalValue else { return nil }
    self = value
  }
}
extension Bool: TLAValueType {
  public static var formalValueShape: FormalValueShape { .boolean }
  public static var defaultValue: Bool { false }
  public init?(formalValue: TLAValue) {
    guard case .bool(let value) = formalValue else { return nil }
    self = value
  }
}
extension String: TLAValueType {
  public static var formalValueShape: FormalValueShape { .string }
  public static var defaultValue: String { "" }
  public init?(formalValue: TLAValue) {
    guard case .string(let value) = formalValue else { return nil }
    self = value
  }
}

extension TLAValueType where Self: RawRepresentable, Self.RawValue == Int {
  public var tlaValue: TLAValue { .int(rawValue) }
  public init?(formalValue: TLAValue) {
    guard case .int(let rawValue) = formalValue,
          let value = Self(rawValue: rawValue),
          value.sourceIssue == nil, value.tlaValue == formalValue else { return nil }
    self = value
  }
}

extension TLAValueType where Self: RawRepresentable, Self.RawValue == String {
  public var tlaValue: TLAValue { .string(rawValue) }
  public init?(formalValue: TLAValue) {
    let rawValue: String
    switch formalValue {
    case .string(let value), .constant(let value): rawValue = value
    default: return nil
    }
    guard let value = Self(rawValue: rawValue),
          value.sourceIssue == nil, value.tlaValue == formalValue else { return nil }
    self = value
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

// MARK: - Expr<T>

/// A formal expression whose value type is known to Swift.
public protocol TypedExpression<ExpressionValue>: StateExprConvertible, Sendable {
  associatedtype ExpressionValue: TLAValueType
  var expr: Expr<ExpressionValue> { get }
}

/// Phantom-typed expression: `Expr<Int>` can only be assigned to `Var<Int>`.
public struct Expr<T: TLAValueType>: TypedExpression {
  public var expr: Self { self }
  public let raw: StateExpr
  public init(_ raw: StateExpr) { self.raw = raw }
  public init(_ value: T) { raw = value.sourceIssue.map(StateExpr.sourceIssue) ?? .value(value.tlaValue) }
  public var stateExpr: StateExpr { raw }


}

extension Expr: ExpressibleByBooleanLiteral where T == Bool {
  public init(booleanLiteral value: Bool) { self.init(value) }
}

public struct Var<T: TLAValueType>: Sendable, CustomStringConvertible, SpecComponent {
  public let name: String
  public let initial: TLAValue?
  public let sourceIssue: SourceModelIssue?

  public init(_ name: String, _ value: T) {
    self.name = name
    self.initial = value.tlaValue
    self.sourceIssue = value.sourceIssue
  }
  public init(_ name: String? = nil, _ initial: TLAValue? = nil) {
    self.name = name ?? ""
    self.initial = initial
    self.sourceIssue = nil
  }
  public var description: String { name }
  /// Type-safe assignment: `Var<Int>.becomes(5)` — only values matching T.
  @discardableResult
  public func becomes(_ value: T) -> ActionExpr { .assign(.named(name), .value(value.tlaValue)) }
  /// Type-safe assignment: `Var<Int>.becomes(x + 1)` — an expression with value type T.
  @discardableResult
  public func becomes(_ expr: some TypedExpression<T>) -> ActionExpr { .assign(.named(name), expr.stateExpr) }
  /// Returns `UNCHANGED x` — the variable stays the same in the next state.
  public var stays: ActionExpr { .unchanged(.named(name)) }

}

extension Var: TypedExpression {
  public var expr: Expr<T> { Expr(stateExpr) }
}

/// Attaches a guard condition to an action.
/// `x.becomes(1).when(x == 0)` produces `(x == 0) /\ x' = 1`.
extension ActionExpr {
  @discardableResult
  public func when(_ condition: some TypedExpression<Bool>) -> ActionExpr {
    .and(.guard_(condition.stateExpr), self)
  }
}

public protocol StateExprConvertible { var stateExpr: StateExpr { get } }
extension StateExpr: StateExprConvertible { public var stateExpr: StateExpr { self } }
extension Var: StateExprConvertible { public var stateExpr: StateExpr { .variable(name) } }

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

// MARK: - Arithmetic (Var<Int> only)

// Raw operators are confined to explicit formal expressions.
extension StateExpr {
  public static func +(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .add(lhs, rhs) }
  public static func -(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .subtract(lhs, rhs) }
  public static func *(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .multiply(lhs, rhs) }
  public static func /(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .divide(lhs, rhs) }
  public static func %(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .modulo(lhs, rhs) }
  public static func ==(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .equal(lhs, rhs) }
  public static func !=(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .notEqual(lhs, rhs) }
  public static func <(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .lessThan(lhs, rhs) }
  public static func <=(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .lessOrEqual(lhs, rhs) }
  public static func >(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .greaterThan(lhs, rhs) }
  public static func >=(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .greaterOrEqual(lhs, rhs) }
  public static func &&(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .and(lhs, rhs) }
  public static func ||(lhs: StateExpr, rhs: StateExpr) -> StateExpr { .or(lhs, rhs) }
  public static prefix func -(value: StateExpr) -> StateExpr { .negate(value) }
  public static prefix func !(value: StateExpr) -> StateExpr { .not(value) }
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
  public static func any(from set: StateExpr) -> StateExpr {
    let qv = generatedBinderName()
    return .choose(set, qv, .value(.bool(true)))
  }
  public static func tuple(_ elements: [some StateExprConvertible]) -> StateExpr {
    .tupleLiteral(elements.map(\.stateExpr))
  }
  public static func record(_ fields: [String: StateExpr]) -> StateExpr { .recordLiteral(.init(fields)) }
  public static func enabled(_ action: ActionDecl) -> StateExpr { .enabledAction(action.name) }

  // MARK: - Var-based bound variables

  public static func forAll(
    _ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    .forAll(set, variable.name, body)
  }
  public static func exists(
    _ variable: Var<some TLAValueType>, in set: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    .exists(set, variable.name, body)
  }
  public static func choose(
    _ variable: Var<some TLAValueType>, from set: StateExpr, matching predicate: StateExpr
  ) -> StateExpr {
    .choose(set, variable.name, predicate)
  }
  public static func functionLiteral(
    _ variable: Var<some TLAValueType>, in domain: StateExpr, _ body: StateExpr
  ) -> StateExpr {
    .functionLiteral(domain, variable.name, body)
  }

  // MARK: - Closure-based with InvariantBuilder context

  public static func forAll(
    _ set: StateExpr,
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
    @InvariantBuilder _ body: (StateExpr) -> StateExpr
  )
    -> StateExpr {
    let qv = generatedBinderName(file: file, line: line, column: column)
    return .forAll(set, qv, body(.variable(qv)))
  }
}

extension ActionExpr {
  /// Chooses a member for an explicit lexical binding. Pass that binding to
  /// guards, assignments, and operator arguments; model variables still read
  /// their current-state values throughout the action.
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

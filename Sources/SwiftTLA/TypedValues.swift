public protocol FiniteTLAValueDomain: TLAValueType, Hashable, Sendable {
  static var finiteValues: [Self] { get }
}

extension FiniteTLAValueDomain {
  public static var formalValueShape: FormalValueShape {
    .finite(typeName: String(describing: Self.self), values: tlaValues)
  }
  static var sourceIssue: SourceModelIssue? {
    let values = finiteValues
    let tlaValues = values.map(\.tlaValue)
    guard !values.isEmpty else {
      return .finiteDomain(type: String(reflecting: Self.self), problem: "no finite values")
    }
    guard Set(tlaValues).count == tlaValues.count else {
      return .finiteDomain(type: String(reflecting: Self.self), problem: "duplicate formal values")
    }
    return nil
  }

  public static var tlaValues: [TLAValue] {
    finiteValues.map(\.tlaValue)
  }
}

public protocol TLARecordSchema: Sendable {
  associatedtype Fields
  static var fields: [TLARecordFieldDeclaration<Self>] { get }
  static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String?
}

public struct TLARecordFieldDeclaration<Schema: TLARecordSchema>: Sendable {
  fileprivate let name: String
  fileprivate let defaultValue: any TLAValueType
  fileprivate let shape: FormalValueShape
  fileprivate let decode: @Sendable (TLAValue) -> (any TLAValueType)?

  public init<Value: TLAValueType>(
    _ field: TLAField<Schema, Value>,
    default defaultValue: Value
  ) {
    name = field.name
    shape = Value.formalValueShape
    self.defaultValue = defaultValue
    decode = { rawValue in
      guard let value = Value(formalValue: rawValue), value.sourceIssue == nil else { return nil }
      return value
    }
  }
}

public struct TLAField<Schema: TLARecordSchema, Value: TLAValueType>: Hashable, Sendable {
  public let name: String
  fileprivate let sourceIssue: SourceModelIssue?

  fileprivate init(name: String, sourceIssue: SourceModelIssue? = nil) {
    self.name = name
    self.sourceIssue = sourceIssue
  }

  private var issue: SourceModelIssue? {
    sourceIssue ?? (Schema.fields.contains { $0.name == name }
      ? nil
      : .recordField(schema: String(reflecting: Schema.self)))
  }

  func recordAccess(_ record: StateExpr) -> StateExpr {
    issue.map(StateExpr.sourceIssue) ?? .recordAccess(record, name)
  }

  fileprivate var recordSelector: StateExpr {
    issue.map(StateExpr.sourceIssue) ?? .value(.string(name))
  }

  fileprivate func value(_ expression: StateExpr) -> StateExpr {
    issue.map(StateExpr.sourceIssue) ?? expression
  }
}

extension TLARecordSchema {
  public static func field<Value: TLAValueType>(_ field: KeyPath<Fields, Value>) -> TLAField<
    Self, Value
  > {
    guard let name = fieldName(for: field), !name.isEmpty else {
      return TLAField(name: "", sourceIssue: .recordField(schema: String(reflecting: Self.self)))
    }
    return TLAField(name: name)
  }
}

public struct TLARecordEntry<Schema: TLARecordSchema>: Sendable {
  fileprivate let name: String
  fileprivate let value: StateExpr

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: Value) {
    self.name = field.name
    self.value = field.value(value.stateExpr)
  }

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: some TypedExpression<Value>) {
    self.name = field.name
    self.value = field.value(value.stateExpr)
  }

}

public struct Record<Schema: TLARecordSchema>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .record(Schema.fields.sorted { $0.name < $1.name }.map { .init(name: $0.name, shape: $0.shape) }) }
  private let values: [(name: String, value: any TLAValueType)]
  public let sourceIssue: SourceModelIssue?

  public init() {
    let declarations = Schema.fields
    values = declarations.map { ($0.name, $0.defaultValue) }
    sourceIssue = Self.schemaProblem(declarations.map(\.name)).map {
      .invalidRecordSchema(schema: String(reflecting: Schema.self), problem: $0)
    } ?? declarations.lazy.compactMap { $0.defaultValue.sourceIssue }.first
  }

  public init?(formalValue: TLAValue) {
    let declarations = Schema.fields
    let declaredNames = declarations.map(\.name)
    guard Self.schemaProblem(declaredNames) == nil,
          case .record(let record) = formalValue,
          record.fields.count == declarations.count,
          Set(record.fields.map(\.name)) == Set(declaredNames)
    else { return nil }
    var values: [(name: String, value: any TLAValueType)] = []
    for declaration in declarations {
      guard let rawValue = record.value(named: declaration.name),
            let value = declaration.decode(rawValue)
      else { return nil }
      values.append((declaration.name, value))
    }
    self.values = values
    sourceIssue = nil
  }

  public var tlaValue: TLAValue {
    .record(TLARecord(values.map { .init($0.name, $0.value.tlaValue) }))
  }
  public static var defaultValue: Self { Self() }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceIssue == rhs.sourceIssue && lhs.tlaValue == rhs.tlaValue
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(sourceIssue)
    hasher.combine(tlaValue)
  }

  public func value<Value: TLAValueType>(for field: TLAField<Schema, Value>) -> Value? {
    values.first { $0.name == field.name }?.value as? Value
  }

  public static func literal(_ fields: TLARecordEntry<Schema>...) -> Expr<Self> {
    if let problem = schemaProblem(Schema.fields.map(\.name)) {
      return Expr(.sourceIssue(.invalidRecordSchema(
        schema: String(reflecting: Schema.self),
        problem: problem
      )))
    }
    let names = fields.map(\.name)
    let duplicates = Dictionary(grouping: names, by: { $0 })
      .compactMap { $0.value.count > 1 ? $0.key : nil }
      .sorted()
    let missing = Set(Schema.fields.map(\.name)).subtracting(names).sorted()
    guard duplicates.isEmpty, missing.isEmpty else {
      return Expr(.sourceIssue(.recordLiteral(
        schema: String(reflecting: Schema.self),
        duplicateFields: duplicates,
        missingFields: missing
      )))
    }
    return Expr(
      StateExpr.record(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })))
  }

  private static func schemaProblem(_ names: [String]) -> String? {
    if names.contains(where: \.isEmpty) { return "a field has an empty name" }
    if Set(names).count != names.count { return "field names are not unique" }
    return nil
  }
}

public struct Function<Domain: FiniteTLAValueDomain, Range: TLAValueType>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .unsupported("total Function view") }
  private let values: [Domain: Range]
  public let sourceIssue: SourceModelIssue?

  public init() {
    let value = Range.defaultValue
    sourceIssue = Domain.sourceIssue ?? value.sourceIssue
    values = Domain.finiteValues.reduce(into: [:]) { $0[$1] = value }
  }

  public init?(formalValue: TLAValue) {
    guard Domain.sourceIssue == nil,
          case .function(let entries) = formalValue,
          Set(entries.keys) == Set(Domain.tlaValues)
    else { return nil }
    var values: [Domain: Range] = [:]
    for (rawKey, rawValue) in entries {
      guard let key = Domain(formalValue: rawKey), key.sourceIssue == nil,
            let value = Range(formalValue: rawValue), value.sourceIssue == nil,
            values.updateValue(value, forKey: key) == nil
      else { return nil }
    }
    self.values = values
    sourceIssue = nil
  }

  public var tlaValue: TLAValue {
    .function(values.reduce(into: [:]) { $0[$1.key.tlaValue] = $1.value.tlaValue })
  }
  public static var defaultValue: Self { Self() }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceIssue == rhs.sourceIssue && lhs.tlaValue == rhs.tlaValue
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(sourceIssue)
    hasher.combine(tlaValue)
  }

  public subscript(_ key: Domain) -> Range? { values[key] }

  public static func literal(_ entries: (Domain, any TypedExpression<Range>)...) -> Expr<Self> {
    literal(entries)
  }

  /// Constructs a total finite function from concrete Swift values.
  public static func literal(_ entries: (Domain, Range)...) -> Expr<Self> {
    literal(entries.map { ($0.0, $0.1.expr) })
  }

  private static func literal(_ entries: [(Domain, any TypedExpression<Range>)]) -> Expr<Self> {
    if let issue = Domain.sourceIssue {
      return Expr(.sourceIssue(issue))
    }
    let keys = entries.map { $0.0.tlaValue }
    let domain = Domain.tlaValues
    let duplicates = Dictionary(grouping: keys, by: { $0 })
      .compactMap { $0.value.count > 1 ? $0.key : nil }
      .sorted()
    let missing = Set(domain).subtracting(keys).sorted()
    guard duplicates.isEmpty, missing.isEmpty else {
      return Expr(.sourceIssue(.functionLiteral(
        domain: String(reflecting: Domain.self),
        duplicateValues: duplicates.map(\.description),
        missingValues: missing.map(\.description)
      )))
    }

    let binding = "_typedFunctionEntry"
    let pairs = entries.flatMap { entry in
      [StateExpr.equal(.variable(binding), entry.0.stateExpr), entry.1.stateExpr]
    }
    return Expr(
      .functionLiteral(.setLiteral(domain.map(StateExpr.value)), binding, .caseExpr(pairs, nil)))
  }

}

public struct PartialFunction<Domain: FiniteTLAValueDomain, Range: TLAValueType>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .function(key: Domain.formalValueShape, value: Range.formalValueShape) }
  private let values: [Domain: Range]
  public let sourceIssue: SourceModelIssue?

  public init() {
    values = [:]
    sourceIssue = Domain.sourceIssue
  }

  public init?(formalValue: TLAValue) {
    guard Domain.sourceIssue == nil,
          case .function(let entries) = formalValue,
          Set(entries.keys).isSubset(of: Set(Domain.tlaValues))
    else { return nil }
    var values: [Domain: Range] = [:]
    for (rawKey, rawValue) in entries {
      guard let key = Domain(formalValue: rawKey), key.sourceIssue == nil,
            let value = Range(formalValue: rawValue), value.sourceIssue == nil,
            values.updateValue(value, forKey: key) == nil
      else { return nil }
    }
    self.values = values
    sourceIssue = nil
  }

  public var tlaValue: TLAValue {
    .function(values.reduce(into: [:]) { $0[$1.key.tlaValue] = $1.value.tlaValue })
  }
  public static var defaultValue: Self { Self() }
  public static var empty: Expr<Self> { Self().expr }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceIssue == rhs.sourceIssue && lhs.tlaValue == rhs.tlaValue
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(sourceIssue)
    hasher.combine(tlaValue)
  }

  public subscript(_ key: Domain) -> Range? { values[key] }

  public static func literal(_ entries: (Domain, any TypedExpression<Range>)...) -> Expr<Self> {
    literal(entries)
  }

  public static func literal(_ entries: (Domain, Range)...) -> Expr<Self> {
    literal(entries.map { ($0.0, $0.1.expr) })
  }

  private static func literal(_ entries: [(Domain, any TypedExpression<Range>)]) -> Expr<Self> {
    if let issue = Domain.sourceIssue {
      return Expr(.sourceIssue(issue))
    }
    let keys = entries.map { $0.0.tlaValue }
    let duplicates = Dictionary(grouping: keys, by: { $0 })
      .compactMap { $0.value.count > 1 ? $0.key : nil }
      .sorted()
    guard duplicates.isEmpty else {
      return Expr(.sourceIssue(.functionLiteral(
        domain: String(reflecting: Domain.self),
        duplicateValues: duplicates.map(\.description),
        missingValues: []
      )))
    }
    guard entries.isEmpty == false else {
      return Expr(.value(.function([:])))
    }
    let binding = "_typedPartialFunctionEntry"
    let pairs = entries.flatMap { entry in
      [StateExpr.equal(.variable(binding), entry.0.stateExpr), entry.1.stateExpr]
    }
    return Expr(.functionLiteral(.setLiteral(keys.map(StateExpr.value)), binding, .caseExpr(pairs, nil)))
  }
}

/// The formal range of a finite function, using the upstream `Functions.Range`
/// operator when that module is imported by the surrounding specification.
public func Range<Domain: FiniteTLAValueDomain, Value: TLAValueType>(
  _ function: some TypedExpression<Function<Domain, Value>>
) -> Expr<SetExpr<Value>> {
  FormalCall("Range", function)
}

/// Chooses an injective sequence containing exactly the members of a formal set.
///
/// This is the standard TLA+ `CHOOSE f \in [1..Cardinality(S) -> S] :
/// IsInjective(f)` expression. The choice remains symbolic in the formal
/// specification and is evaluated by the compiled runtime.
public func InjectiveSequence<Element: TLAValueType>(
  from values: some TypedExpression<SetExpr<Element>>
) -> Expr<TupleExpr<Element>> {
  Expr(.choose(
    .functionSet(.integerRange(.int(1), .cardinality(values.stateExpr)), values.stateExpr),
    "f",
    .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
  ))
}

/// The bounded TLA+ function space from one finite domain to a finite set of
/// values.
public func Functions<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
  from domain: FiniteDomain<Domain>,
  to values: some TypedExpression<SetExpr<Range>>
) -> Expr<SetExpr<Function<Domain, Range>>> {
  Expr(.functionSet(.setLiteral(domain.members.map(\.stateExpr)), values.stateExpr))
}

/// All subsets of a finite formal set.
public func Subsets<Element: TLAValueType>(
  of values: some TypedExpression<SetExpr<Element>>
) -> Expr<SetExpr<SetExpr<Element>>> {
  Expr(.powerSet(values.stateExpr))
}

// swiftlint:disable identifier_name
/// All non-empty subsets of a finite formal set.
///
/// The choice domain used by a PlusCal `with` statement such as
/// `rk \in SUBSET Key \ { { } }`.
public func NonEmptySubsets<Element: TLAValueType>(
  of values: some TypedExpression<SetExpr<Element>>
) -> Expr<SetExpr<SetExpr<Element>>> {
  let emptySet = StateExpr.setLiteral([])
  return Expr(.setDifference(.powerSet(values.stateExpr), .setLiteral([emptySet])))
}
// swiftlint:enable identifier_name

/// Narrows a finite formal set with a typed TLA+ predicate.
public func Where<Value: TLAValueType, Predicate: TypedExpression<Bool>>(
  _ candidates: some TypedExpression<SetExpr<Value>>,
  file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
  matching predicate: (WithValue<Value>) -> Predicate
) -> Expr<SetExpr<Value>> {
  let binding = generatedBinderName(file: file, line: line, column: column)
  return Expr(.setFilter(
    candidates.stateExpr,
    binding,
    predicate(WithValue<Value>(expression: .variable(binding))).stateExpr
  ))
}

/// Selects one value from a finite formal domain.
///
/// The choice remains symbolic and is evaluated against the current model state.
public func Select<Value: TLAValueType, Predicate: TypedExpression<Bool>>(
  from candidates: some TypedExpression<SetExpr<Value>>,
  file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
  matching predicate: (WithValue<Value>) -> Predicate
) -> Expr<Value> {
  let binding = generatedBinderName(file: file, line: line, column: column)
  return Expr(.choose(
    candidates.stateExpr,
    binding,
    predicate(WithValue<Value>(expression: .variable(binding))).stateExpr
  ))
}

public struct SetExpr<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .set(Element.formalValueShape) }
  /// The typed members of this finite formal set. Their order is unspecified.
  public let elements: [Element]
  public let sourceIssue: SourceModelIssue?

  public init() {
    elements = []
    sourceIssue = nil
  }

  /// A closed, typed finite set value.
  public init(_ elements: Element...) {
    sourceIssue = elements.lazy.compactMap(\.sourceIssue).first
    guard sourceIssue == nil else {
      self.elements = elements
      return
    }
    var members: Set<TLAValue> = []
    self.elements = elements.filter { members.insert($0.tlaValue).inserted }
  }

  public init?(formalValue: TLAValue) {
    guard case .set(let values) = formalValue else { return nil }
    var elements: [Element] = []
    for value in values {
      guard let element = Element(formalValue: value), element.sourceIssue == nil else { return nil }
      elements.append(element)
    }
    self.elements = elements
    sourceIssue = nil
  }

  public var tlaValue: TLAValue { .set(Set(elements.map(\.tlaValue))) }
  public static var defaultValue: Self { Self() }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceIssue == rhs.sourceIssue && lhs.tlaValue == rhs.tlaValue
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(sourceIssue)
    hasher.combine(tlaValue)
  }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    Expr(.setLiteral(elements.map(\.stateExpr)))
  }

  public static func literal(_ elements: any TypedExpression<Element>...) -> Expr<Self> {
    Expr(.setLiteral(elements.map(\.stateExpr)))
  }
}

public protocol FormalSetValue: TLAValueType {}
extension SetExpr: FormalSetValue {}

extension TypedExpression where ExpressionValue: FormalSetValue {
  public func intersection<Element: TLAValueType>(
    _ other: some TypedExpression<ExpressionValue>
  ) -> Expr<SetExpr<Element>> where ExpressionValue == SetExpr<Element> {
    Expr(.intersection(stateExpr, other.stateExpr))
  }

  public var isEmpty: Expr<Bool> {
    Expr(.equal(.cardinality(stateExpr), .value(.int(0))))
  }

  public var cardinality: Expr<Int> {
    Expr<Int>(.cardinality(stateExpr))
  }

  public func isSubset(of other: some TypedExpression<ExpressionValue>) -> Expr<Bool> {
    Expr(stateExpr.isSubset(of: other))
  }
}

/// A typed finite TLA+ tuple (sequence).
///
/// Use this typed formal sequence for ordered state.
public struct TupleExpr<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .sequence(Element.formalValueShape) }
  /// The typed tuple elements, in their formal order.
  public let elements: [Element]

  public init() {
    elements = []
  }

  public init?(formalValue: TLAValue) {
    guard case .tuple(let values) = formalValue else { return nil }
    var elements: [Element] = []
    for value in values {
      guard let element = Element(formalValue: value), element.sourceIssue == nil else { return nil }
      elements.append(element)
    }
    self.elements = elements
  }

  public var tlaValue: TLAValue { .tuple(elements.map(\.tlaValue)) }
  public static var defaultValue: Self { Self() }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.tlaValue == rhs.tlaValue }
  public func hash(into hasher: inout Hasher) { hasher.combine(tlaValue) }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    Expr(.tupleLiteral(elements.map(\.stateExpr)))
  }

  public static func literal(_ elements: any TypedExpression<Element>...) -> Expr<Self> {
    Expr(.tupleLiteral(elements.map(\.stateExpr)))
  }
}

public protocol FormalTupleValue: TLAValueType {}
extension TupleExpr: FormalTupleValue {}

/// A typed two-member TLA+ tuple.
///
/// Use `Pair` when the two positions have different formal types. It can be
/// stored in formal state, used as a set member, and selected by a PlusCal
/// `with` binding.
public struct Pair<First: TLAValueType, Second: TLAValueType>: TLAValueType, Hashable, Sendable {
  public static var formalValueShape: FormalValueShape { .tuple([First.formalValueShape, Second.formalValueShape]) }
  public let first: First
  public let second: Second

  public init(first: First = .defaultValue, second: Second = .defaultValue) {
    self.first = first
    self.second = second
  }

  public init?(formalValue: TLAValue) {
    guard case .tuple(let values) = formalValue,
          values.count == 2,
          let first = First(formalValue: values[0]),
          let second = Second(formalValue: values[1]),
          first.sourceIssue == nil, second.sourceIssue == nil
    else { return nil }
    self.first = first
    self.second = second
  }

  public var sourceIssue: SourceModelIssue? { first.sourceIssue ?? second.sourceIssue }
  public var tlaValue: TLAValue { .tuple([first.tlaValue, second.tlaValue]) }
  public static var defaultValue: Self { Self() }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sourceIssue == rhs.sourceIssue && lhs.tlaValue == rhs.tlaValue
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(sourceIssue)
    hasher.combine(tlaValue)
  }

  public static func literal(_ first: First, _ second: Second) -> Expr<Self> {
    Expr(.tupleLiteral([first.stateExpr, second.stateExpr]))
  }

  public static func literal(_ first: some TypedExpression<First>, _ second: some TypedExpression<Second>) -> Expr<Self> {
    Expr(.tupleLiteral([first.stateExpr, second.stateExpr]))
  }
}

extension Pair: FormalTupleValue {}

/// A finite formal sequence whose first element is at index zero.
///
/// TLA+ represents this value as a function with domain `0..<(count)` for
/// source algorithms that use `ZSequences`.
public struct ZeroBasedSequence<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let elements: [Element]

  public init() {
    elements = []
  }

  public init?(formalValue: TLAValue) {
    guard case .function(let values) = formalValue else { return nil }
    var elements: [Element] = []
    for index in 0..<values.count {
      guard let value = values[.int(index)],
            let element = Element(formalValue: value), element.sourceIssue == nil
      else { return nil }
      elements.append(element)
    }
    self.elements = elements
  }

  public var tlaValue: TLAValue {
    .function(Dictionary(uniqueKeysWithValues: elements.enumerated().map {
      (.int($0.offset), $0.element.tlaValue)
    }))
  }
  public static var defaultValue: Self { Self() }
  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.tlaValue == rhs.tlaValue }
  public func hash(into hasher: inout Hasher) { hasher.combine(tlaValue) }

  public func element(at index: Int) -> Element? {
    elements.indices.contains(index) ? elements[index] : nil
  }

  /// Creates a zero-based formal sequence from values in formal order.
  public static func literal() -> Expr<Self> {
    Expr(.value(.function([:])))
  }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    literal(elements.map(\.stateExpr))
  }

  public static func literal(_ elements: any TypedExpression<Element>...) -> Expr<Self> {
    literal(elements.map(\.stateExpr))
  }

  /// Creates a zero-based formal sequence with the supplied formal length.
  ///
  /// The length and value may depend on earlier formal state. No application
  /// code executes when the sequence is built.
  public static func filled(
    length: some TypedExpression<Int>,
    with value: some TypedExpression<Element>
  ) -> Expr<Self> {
    let index = "__zeroBasedSequenceIndex"
    return Expr(.functionLiteral(
      .integerRange(.int(0), .subtract(length.stateExpr, .int(1))),
      index,
      value.stateExpr
    ))
  }

  public static func filled(length: some TypedExpression<Int>, with value: Element) -> Expr<Self> {
    filled(length: length, with: value.expr)
  }

  private static func literal(_ elements: [StateExpr]) -> Expr<Self> {
    Expr(formalZeroBasedSequence(elements))
  }
}

public protocol FormalZeroBasedSequenceValue: TLAValueType {}
extension ZeroBasedSequence: FormalZeroBasedSequenceValue {}

/// Creates a finite formal set of sequences for model checking.
///
/// `Sequences(of:lengths:)` is the bounded authoring form of TLA+ `Seq(S)`.
/// The element domain and every permitted length are explicit, so the result
/// remains finite and can be explored by the checker and TLC.
// swiftlint:disable:next identifier_name
public func Sequences<Element: TLAValueType>(
  of elements: some TypedExpression<SetExpr<Element>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<TupleExpr<Element>>> {
  guard case .setLiteral(let members) = elements.stateExpr else {
    return Expr(.sourceIssue(.sequenceElementDomain(operation: "Sequences")))
  }
  guard lengths.lowerBound >= 0 else {
    return Expr(.sourceIssue(.negativeSequenceLength(operation: "Sequences", lowerBound: lengths.lowerBound)))
  }

  let sequences = formalSequenceExpressions(members: members, lengths: lengths)
  return Expr<SetExpr<TupleExpr<Element>>>(.setLiteral(sequences))
}

/// Creates a finite formal set of zero-based sequences for model checking.
///
/// This is the bounded form of a `ZSeq(S)` input domain. The returned values
/// have function domains `0..<(length)`, so indexing at zero stays formal.
public func ZeroBasedSequences<Element: TLAValueType>(
  of elements: some TypedExpression<SetExpr<Element>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<ZeroBasedSequence<Element>>> {
  guard case .setLiteral(let members) = elements.stateExpr else {
    return Expr(.sourceIssue(.sequenceElementDomain(operation: "ZeroBasedSequences")))
  }
  guard lengths.lowerBound >= 0 else {
    return Expr(.sourceIssue(.negativeSequenceLength(operation: "ZeroBasedSequences", lowerBound: lengths.lowerBound)))
  }
  return Expr(.setLiteral(formalZeroBasedSequenceExpressions(members: members, lengths: lengths)))
}

/// Creates a finite formal set of nondecreasing integer sequences.
///
/// This is the bounded model-checking form of a sorted `Seq(Values)` domain.
/// Use it when sortedness is a declared input assumption, as in binary search.
// swiftlint:disable:next identifier_name
public func SortedSequences(
  of elements: some TypedExpression<SetExpr<Int>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<TupleExpr<Int>>> {
  guard case .setLiteral(let members) = elements.stateExpr else {
    return Expr(.sourceIssue(.sequenceElementDomain(operation: "SortedSequences")))
  }
  guard lengths.lowerBound >= 0 else {
    return Expr(.sourceIssue(.negativeSequenceLength(operation: "SortedSequences", lowerBound: lengths.lowerBound)))
  }
  return Expr<SetExpr<TupleExpr<Int>>>(.setLiteral(
    formalSequenceExpressions(members: members, lengths: lengths).filter(formalIntegerSequenceIsSorted)
  ))
}

/// The finite sequence-domain expansion shared by the builder and source
/// parser.
package func formalSequenceExpressions(
  members: [StateExpr],
  lengths: ClosedRange<Int>
) -> [StateExpr] {
  guard lengths.lowerBound >= 0 else { return [] }

  var sequences: [StateExpr] = []
  for length in lengths {
    var prefixes: [[StateExpr]] = [[]]
    for _ in 0..<length {
      prefixes = prefixes.flatMap { prefix in
        members.map { prefix + [$0] }
      }
    }
    sequences += prefixes.map(StateExpr.tupleLiteral)
  }
  return sequences
}

package func formalZeroBasedSequenceExpressions(
  members: [StateExpr],
  lengths: ClosedRange<Int>
) -> [StateExpr] {
  guard lengths.lowerBound >= 0 else { return [] }
  return formalSequenceExpressions(members: members, lengths: lengths).map { tuple in
    guard case .tupleLiteral(let elements) = tuple else { return tuple }
    return formalZeroBasedSequence(elements)
  }
}

/// The index domain guarantees that exactly one CASE branch matches.
package func formalZeroBasedSequence(_ elements: [StateExpr]) -> StateExpr {
  guard !elements.isEmpty else { return .value(.function([:])) }
  let index = "__zeroBasedSequenceIndex"
  let branches = elements.enumerated().flatMap { offset, element in
    [StateExpr.equal(.variable(index), .int(offset)), element]
  }
  return .functionLiteral(
    .setLiteral(elements.indices.map { .int($0) }), index, .caseExpr(branches, nil))
}

package func formalIntegerSequenceIsSorted(_ expression: StateExpr) -> Bool {
  guard case .tupleLiteral(let values) = expression else { return false }
  let integers = values.compactMap { value -> Int? in
    guard case .value(.int(let integer)) = value else { return nil }
    return integer
  }
  return integers.count == values.count
    && zip(integers, integers.dropFirst()).allSatisfy { $0 <= $1 }
}

extension TypedExpression {
  /// Returns the formal union of two typed sets.
  public func union<Element: TLAValueType>(
    _ other: some TypedExpression<SetExpr<Element>>
  ) -> Expr<SetExpr<Element>> where ExpressionValue == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(stateExpr, other.stateExpr))
  }

  public func subtracting<Element: TLAValueType>(
    _ other: some TypedExpression<SetExpr<Element>>
  ) -> Expr<SetExpr<Element>> where ExpressionValue == SetExpr<Element> {
    Expr(.setDifference(stateExpr, other.stateExpr))
  }

  public func inserting<Element: TypedExpression>(_ element: Element) -> Expr<SetExpr<Element.ExpressionValue>>
  where ExpressionValue == SetExpr<Element.ExpressionValue> {
    Expr<SetExpr<Element.ExpressionValue>>(.union(stateExpr, .setLiteral([element.stateExpr])))
  }

  public func inserting<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
  where ExpressionValue == SetExpr<Element> {
    inserting(element.expr)
  }

  public func removing<Element: TLAValueType>(_ element: some TypedExpression<Element>) -> Expr<SetExpr<Element>>
  where ExpressionValue == SetExpr<Element> {
    Expr<SetExpr<Element>>(.setDifference(stateExpr, .setLiteral([element.stateExpr])))
  }

  public func contains<Element: TypedExpression>(_ element: Element) -> Expr<Bool>
  where ExpressionValue == SetExpr<Element.ExpressionValue> {
    Expr(.in(element.stateExpr, stateExpr))
  }

  public func contains<Element: TLAValueType>(_ element: Element) -> Expr<Bool>
  where ExpressionValue == SetExpr<Element> {
    contains(element.expr)
  }

  public func appending<Element: TypedExpression>(_ element: Element) -> Expr<TupleExpr<Element.ExpressionValue>>
  where ExpressionValue == TupleExpr<Element.ExpressionValue> {
    Expr<TupleExpr<Element.ExpressionValue>>(.tupleAppend(stateExpr, element.stateExpr))
  }

  public func appending<Element: TLAValueType>(_ element: Element) -> Expr<TupleExpr<Element>>
  where ExpressionValue == TupleExpr<Element> {
    appending(element.expr)
  }

  /// Concatenates two formal one-based sequences.
  ///
  /// The right side may be a finite function selected by `CHOOSE`; TLA+
  /// defines that function as a sequence when its domain is `1..n`.
  public func concatenating<Element: TLAValueType>(
    _ other: some TypedExpression<TupleExpr<Element>>
  ) -> Expr<TupleExpr<Element>> where ExpressionValue == TupleExpr<Element> {
    Expr<TupleExpr<Element>>(.tupleConcatenate(stateExpr, other.stateExpr))
  }

  public func removing<Element: TLAValueType>(at index: some TypedExpression<Int>) -> Expr<TupleExpr<Element>>
  where ExpressionValue == TupleExpr<Element> {
    Expr(.tupleRemoving(stateExpr, index.stateExpr))
  }

  public func at<Element: TLAValueType>(_ index: Int) -> Expr<Element> where ExpressionValue == TupleExpr<Element> {
    Expr<Element>(.tupleAccess(stateExpr, index))
  }

  public func first<First: TLAValueType, Second: TLAValueType>() -> Expr<First>
  where ExpressionValue == Pair<First, Second> {
    Expr<First>(.tupleAccess(stateExpr, 1))
  }

  public func second<First: TLAValueType, Second: TLAValueType>() -> Expr<Second>
  where ExpressionValue == Pair<First, Second> {
    Expr<Second>(.tupleAccess(stateExpr, 2))
  }

  /// Reads a formal sequence at a one-based formal index.
  public subscript<Element: TLAValueType>(_ index: some TypedExpression<Int>) -> Expr<Element>
  where ExpressionValue == TupleExpr<Element> {
    Expr<Element>(.tupleDynamicAccess(stateExpr, index.stateExpr))
  }

  public subscript<Schema: TLARecordSchema, FieldValue>(_ field: TLAField<Schema, FieldValue>) -> Expr<FieldValue>
  where ExpressionValue == Record<Schema> {
    Expr<FieldValue>(field.recordAccess(stateExpr))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Domain) -> Expr<
    Range
  > where ExpressionValue == Function<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, finiteDomainIndex(index)))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: some TypedExpression<Domain>) -> Expr<
    Range
  > where ExpressionValue == Function<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, index.stateExpr))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Domain) -> Expr<
    Range
  > where ExpressionValue == PartialFunction<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, finiteDomainIndex(index)))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: some TypedExpression<Domain>) -> Expr<
    Range
  > where ExpressionValue == PartialFunction<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, index.stateExpr))
  }

  public func updating<Schema: TLARecordSchema, FieldValue>(
    _ field: TLAField<Schema, FieldValue>, to value: FieldValue
  ) -> Expr<Record<Schema>> where ExpressionValue == Record<Schema> {
    Expr<Record<Schema>>(.except(stateExpr, field.recordSelector, field.value(value.stateExpr)))
  }

  public func updating<Schema: TLARecordSchema, FieldValue>(
    _ field: TLAField<Schema, FieldValue>, to value: some TypedExpression<FieldValue>
  ) -> Expr<Record<Schema>> where ExpressionValue == Record<Schema> {
    Expr<Record<Schema>>(.except(stateExpr, field.recordSelector, field.value(value.stateExpr)))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: some TypedExpression<Range>
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(stateExpr, finiteDomainIndex(index), value.stateExpr))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: Range
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    updating(index, to: value.expr)
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType, Update: TypedExpression<Range>>(
    _ index: Domain, _ update: (Expr<Range>) -> Update
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    let selected = self[index]
    return Expr<Function<Domain, Range>>(
      .except(stateExpr, finiteDomainIndex(index), update(selected).stateExpr))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: some TypedExpression<Domain>, to value: some TypedExpression<Range>
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.stateExpr))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: some TypedExpression<Domain>, to value: Range
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    updating(index, to: value.expr)
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType, Update: TypedExpression<Range>>(
    _ index: some TypedExpression<Domain>, _ update: (Expr<Range>) -> Update
  ) -> Expr<Function<Domain, Range>> where ExpressionValue == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(
      .except(stateExpr, index.stateExpr, update(Expr<Range>(.functionApply(stateExpr, index.stateExpr))).stateExpr))
  }

  public func overriding<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, with value: some TypedExpression<Range>
  ) -> Expr<PartialFunction<Domain, Range>> where ExpressionValue == PartialFunction<Domain, Range> {
    Expr(.partialFunctionOverriding(stateExpr, key: finiteDomainIndex(index), value: value.stateExpr))
  }

  public func overriding<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, with value: Range
  ) -> Expr<PartialFunction<Domain, Range>> where ExpressionValue == PartialFunction<Domain, Range> {
    overriding(index, with: value.expr)
  }

  public func overriding<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: some TypedExpression<Domain>, with value: some TypedExpression<Range>
  ) -> Expr<PartialFunction<Domain, Range>> where ExpressionValue == PartialFunction<Domain, Range> {
    Expr(.partialFunctionOverriding(stateExpr, key: index.stateExpr, value: value.stateExpr))
  }

  public func removing<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
  where ExpressionValue == SetExpr<Element> {
    Expr(.setDifference(stateExpr, .setLiteral([element.stateExpr])))
  }

  public func overriding<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: some TypedExpression<Domain>, with value: Range
  ) -> Expr<PartialFunction<Domain, Range>> where ExpressionValue == PartialFunction<Domain, Range> {
    overriding(index, with: value.expr)
  }
}

/// A bounded, inclusive TLA+ integer set whose endpoints can depend on state.
public func IntRange(
  _ lower: some TypedExpression<Int>,
  through upper: some TypedExpression<Int>
) -> Expr<SetExpr<Int>> {
  Expr<SetExpr<Int>>(.integerRange(lower.stateExpr, upper.stateExpr))
}

public func IntRange(_ lower: Int, through upper: some TypedExpression<Int>) -> Expr<SetExpr<Int>> {
  IntRange(Expr(lower), through: upper)
}

public func IntRange(_ lower: some TypedExpression<Int>, through upper: Int) -> Expr<SetExpr<Int>> {
  IntRange(lower, through: Expr(upper))
}

public func IntRange(_ lower: Int, through upper: Int) -> Expr<SetExpr<Int>> {
  IntRange(Expr(lower), through: Expr(upper))
}

extension TypedExpression {
  /// Selects formal set members that satisfy `predicate`.
  public func filtering<Element: TLAValueType, Predicate: TypedExpression<Bool>>(
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
    _ predicate: (WithValue<Element>) -> Predicate
  ) -> Expr<SetExpr<Element>> where ExpressionValue == SetExpr<Element> {
    let binding = generatedBinderName(file: file, line: line, column: column)
    let element = WithValue<Element>(expression: .variable(binding))
    return Expr<SetExpr<Element>>(.setFilter(stateExpr, binding, predicate(element).stateExpr))
  }

  /// Maps every formal set member through a typed formal expression.
  public func mapping<Element: TLAValueType, Result: TypedExpression>(
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
    _ transform: (WithValue<Element>) -> Result
  ) -> Expr<SetExpr<Result.ExpressionValue>> where ExpressionValue == SetExpr<Element> {
    let binding = generatedBinderName(file: file, line: line, column: column)
    let element = WithValue<Element>(expression: .variable(binding))
    return Expr<SetExpr<Result.ExpressionValue>>(.setMap(transform(element).stateExpr, binding, stateExpr))
  }
}

extension TypedExpression where ExpressionValue: FormalTupleValue {
  public var count: Expr<Int> {
    Expr<Int>(.tupleLength(stateExpr))
  }
}

extension TypedExpression {
  public func head<Element: TLAValueType>() -> Expr<Element> where ExpressionValue == TupleExpr<Element> {
    Expr<Element>(.tupleHead(stateExpr))
  }
}

extension TypedExpression {
  /// Selects formal sequence members that satisfy `predicate`.
  public func selecting<Element: TLAValueType, Predicate: TypedExpression<Bool>>(
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
    where predicate: (WithValue<Element>) -> Predicate
  ) -> Expr<TupleExpr<Element>> where ExpressionValue == TupleExpr<Element> {
    let binding = generatedBinderName(file: file, line: line, column: column)
    let element = WithValue<Element>(expression: .variable(binding))
    return Expr<TupleExpr<Element>>(.sequenceSelect(stateExpr, binding, predicate(element).stateExpr))
  }
}

/// Combines a formal function with the upstream `Functions.FoldFunction` operator.
///
/// The closure builds a `LAMBDA` in the specification. The upstream operator
/// selects a function-domain member with `CHOOSE`, so the operation must be
/// independent of that selection order. Import `FunctionsModule.module`
/// into the surrounding specification so TLC receives the upstream operator.
public func Fold<Element: TLAValueType, Result: TLAValueType, Combined: TypedExpression<Result>>(
  _ sequence: some TypedExpression<TupleExpr<Element>>,
  startingWith initial: some TypedExpression<Result>,
  file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
  _ combine: (Expr<Element>, Expr<Result>) -> Combined
) -> Expr<Result> {
  let elementName = generatedBinderName(file: file, line: line, column: column &* 2)
  let resultName = generatedBinderName(file: file, line: line, column: (column &* 2) &+ 1)
  let element = Expr<Element>(.variable(elementName))
  let accumulated = Expr<Result>(.variable(resultName))
  return Expr<Result>(
    .foldFunction(
      FormalLambda(
        parameters: [elementName, resultName],
        body: combine(element, accumulated).stateExpr
      ),
      initial: initial.stateExpr,
      sequence: sequence.stateExpr
    )
  )
}

/// Starts a formal fold from a concrete formal value.
public func Fold<Element: TLAValueType, Result: TLAValueType, Combined: TypedExpression<Result>>(
  _ sequence: some TypedExpression<TupleExpr<Element>>,
  startingWith initial: Result,
  file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
  _ combine: (Expr<Element>, Expr<Result>) -> Combined
) -> Expr<Result> {
  Fold(sequence, startingWith: initial.expr, file: file, line: line, column: column, combine)
}

extension TypedExpression where ExpressionValue: FormalZeroBasedSequenceValue {
  /// The formal number of elements in a zero-based sequence.
  public var count: Expr<Int> {
    Expr<Int>(.cardinality(.domain(stateExpr)))
  }
}

extension TypedExpression where ExpressionValue == Int {
  /// Divides formal integers with TLA+ integer-division semantics.
  public func integerDivided(by divisor: Int) -> Expr<Int> {
    Expr(.integerDivide(stateExpr, .int(divisor)))
  }
}

extension TypedExpression {
  /// Reads a formal sequence at a one-based formal index.
  public func at<Element: TLAValueType>(_ index: some TypedExpression<Int>) -> Expr<Element>
  where ExpressionValue == TupleExpr<Element> {
    Expr<Element>(.tupleDynamicAccess(stateExpr, index.stateExpr))
  }

  /// Reads a zero-based formal sequence at a formal index.
  public subscript<Element: TLAValueType>(_ index: some TypedExpression<Int>) -> Expr<Element>
  where ExpressionValue == ZeroBasedSequence<Element> {
    Expr<Element>(.functionApply(stateExpr, index.stateExpr))
  }

  /// Replaces one value in a zero-based formal sequence.
  public func updating<Element: TLAValueType>(
    _ index: some TypedExpression<Int>,
    to value: some TypedExpression<Element>
  ) -> Expr<ZeroBasedSequence<Element>> where ExpressionValue == ZeroBasedSequence<Element> {
    Expr(.except(stateExpr, index.stateExpr, value.stateExpr))
  }

}

extension Var {
  public func inserting<Element: TLAValueType>(_ element: Element) -> ActionExpr
  where T == SetExpr<Element> {
    inserting(element.expr)
  }

  public func inserting<Element: TLAValueType>(_ element: some TypedExpression<Element>) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(.named(name), .union(stateExpr, .setLiteral([element.stateExpr])))
  }

  public func removing<Element: TLAValueType>(_ element: Element) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(.named(name), .setDifference(stateExpr, .setLiteral([element.stateExpr])))
  }

  public func removing<Element: TLAValueType>(_ element: some TypedExpression<Element>) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(.named(name), .setDifference(stateExpr, .setLiteral([element.stateExpr])))
  }
}

private func finiteDomainIndex<Domain: FiniteTLAValueDomain>(_ index: Domain) -> StateExpr {
  if let issue = Domain.sourceIssue {
    return .sourceIssue(issue)
  }
  let value = index.tlaValue
  guard Domain.tlaValues.contains(value) else {
    return .sourceIssue(.finiteDomainValue(
      type: String(reflecting: Domain.self),
      value: value.description
    ))
  }
  return .value(value)
}

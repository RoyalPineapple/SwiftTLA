public protocol FiniteTLAValueDomain: TLAValueType, Hashable, Sendable {
  static var finiteValues: [Self] { get }
}

extension FiniteTLAValueDomain {
  private static var validatedFiniteValues: [Self] {
    let values = finiteValues
    let tlaValues = values.map(\.tlaValue)
    precondition(!values.isEmpty, "\(Self.self) must declare at least one finite value")
    precondition(
      Set(tlaValues).count == tlaValues.count, "\(Self.self) has duplicate finite TLA values")
    return values
  }

  public static var tlaValues: [TLAValue] {
    validatedFiniteValues.map(\.tlaValue)
  }

  public static var defaultValue: Self { validatedFiniteValues[0] }
}

public protocol TLARecordSchema: Sendable {
  associatedtype Fields
  static var fieldNames: Set<String> { get }
  /// A complete, schema-valid formal value used only when a generic default is required.
  static var defaultRecord: TLAValue { get }
  static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String?
}

public struct TLAField<Schema: TLARecordSchema, Value: TLAValueType>: Hashable, Sendable {
  public let name: String
}

extension TLARecordSchema {
  public static func field<Value: TLAValueType>(_ field: KeyPath<Fields, Value>) -> TLAField<
    Self, Value
  > {
    guard let name = fieldName(for: field), !name.isEmpty, fieldNames.contains(name) else {
      preconditionFailure("\(Self.self) does not declare the requested record field")
    }
    return TLAField(name: name)
  }
}

public struct TLARecordEntry<Schema: TLARecordSchema>: Sendable {
  fileprivate let name: String
  fileprivate let value: StateExpr

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: Value) {
    self.name = field.name
    self.value = .value(value.tlaValue)
  }

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: Expr<Value>) {
    self.name = field.name
    self.value = value.raw
  }

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: ProcessIdentifier<Value>)
  where Value: FiniteDomainKey {
    self.name = field.name
    self.value = value.stateExpr
  }

  public init<Value>(_ field: TLAField<Schema, Value>, _ value: WithValue<Value>)
  where Value: TLAValueType {
    self.name = field.name
    self.value = value.stateExpr
  }
}

public struct Record<Schema: TLARecordSchema>: TLAValueType, Hashable, Sendable {
  private let values: [String: TLAValue]

  public init() {
    guard let value = Self(formalValue: Schema.defaultRecord) else {
      preconditionFailure("\(Schema.self).defaultRecord must contain every declared field with valid formal values")
    }
    values = value.values
  }

  public init?(formalValue: TLAValue) {
    guard case .record(let values) = formalValue,
          Set(values.keys) == Schema.fieldNames
    else { return nil }
    self.values = values
  }

  public var tlaValue: TLAValue { .record(values) }
  public static var defaultValue: Self { Self() }

  public subscript<Value: TLAValueType>(_ field: TLAField<Schema, Value>) -> Value {
    guard let raw = values[field.name], let value = Value(formalValue: raw) else {
      preconditionFailure("Formal record '\(Schema.self)' contains an invalid '\(field.name)' field")
    }
    return value
  }

  public static func literal(_ fields: TLARecordEntry<Schema>...) -> Expr<Self> {
    let names = fields.map(\.name)
    precondition(Set(names).count == names.count, "\(Schema.self) record literal repeats a field")
    precondition(
      Set(names) == Schema.fieldNames,
      "\(Schema.self) record literal must contain every declared field")
    return Expr(
      .recordLiteral(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })))
  }
}

public struct Function<Domain: FiniteTLAValueDomain, Range: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let values: [TLAValue: TLAValue]

  public init() {
    values = Dictionary(uniqueKeysWithValues: Domain.tlaValues.map { ($0, Range.defaultValue.tlaValue) })
  }

  public init?(formalValue: TLAValue) {
    guard case .function(let values) = formalValue,
          Set(values.keys) == Set(Domain.tlaValues),
          values.values.allSatisfy({ Range(formalValue: $0) != nil })
    else { return nil }
    self.values = values
  }

  public var tlaValue: TLAValue { .function(values) }
  public static var defaultValue: Self { Self() }

  public subscript(_ key: Domain) -> Range {
    guard let raw = values[key.tlaValue], let value = Range(formalValue: raw) else {
      preconditionFailure("Formal function '\(Domain.self)' contains an invalid value")
    }
    return value
  }

  public static func literal(_ entries: (Domain, Expr<Range>)...) -> Expr<Self> {
    literal(entries)
  }

  /// Constructs a total finite function from concrete Swift values.
  public static func literal(_ entries: (Domain, Range)...) -> Expr<Self> {
    literal(entries.map { ($0.0, Expr<Range>(.value($0.1.tlaValue))) })
  }

  private static func literal(_ entries: [(Domain, Expr<Range>)]) -> Expr<Self> {
    let keys = entries.map { $0.0.tlaValue }
    let domain = Domain.tlaValues
    precondition(
      Set(keys).count == keys.count, "\(Domain.self) function literal repeats a domain value")
    precondition(
      Set(keys) == Set(domain) && keys.count == domain.count,
      "\(Domain.self) function literal must cover its finite domain")

    let binding = "_typedFunctionEntry"
    let pairs = entries.flatMap { entry in
      [StateExpr.equal(.variable(binding), .value(entry.0.tlaValue)), entry.1.raw]
    }
    return Expr(
      .functionLiteral(.setLiteral(domain.map(StateExpr.value)), binding, .caseExpr(pairs, nil)))
  }

}

extension Expr {
  /// The formal range of a finite function, using the upstream `Functions.Range`
  /// operator when that module is imported by the surrounding specification.
  public var range<Domain: FiniteTLAValueDomain, Value: TLAValueType>: Expr<SetExpr<Value>>
  where T == Function<Domain, Value> {
    FormalCall("Range", self)
  }
}

/// The bounded formal function space from one finite domain to a finite set
/// of values. `Functions(from:to:)` is a TLA+ function set, not a Swift
/// dictionary or closure evaluated by the application.
public func Functions<Domain: FiniteDomainKey, Range: TLAValueType>(
  from domain: FiniteDomain<Domain>,
  to values: Expr<SetExpr<Range>>
) -> Expr<SetExpr<Function<Domain, Range>>> {
  Expr(.functionSet(.setLiteral(domain.members.map { .value($0.tlaValue) }), values.raw))
}

/// All subsets of a finite formal set.
public func Subsets<Element: TLAValueType>(
  of values: Expr<SetExpr<Element>>
) -> Expr<SetExpr<SetExpr<Element>>> {
  Expr(.powerSet(values.raw))
}

// swiftlint:disable identifier_name
/// All non-empty subsets of a finite formal set.
///
/// This is the formal choice domain used by a PlusCal `with` statement such
/// as `rk \in SUBSET Key \ { { } }`. It is not a Swift `Set` filter.
public func NonEmptySubsets<Element: TLAValueType>(
  of values: Expr<SetExpr<Element>>
) -> Expr<SetExpr<SetExpr<Element>>> {
  let emptySet = StateExpr.setLiteral([])
  return Expr(.setDifference(.powerSet(values.raw), .setLiteral([emptySet])))
}
// swiftlint:enable identifier_name

/// Narrows a finite formal set to the values that satisfy a formal predicate.
/// The closure describes TLA+ syntax; it does not execute as application code.
public func Where<Value: TLAValueType>(
  _ candidates: Expr<SetExpr<Value>>,
  matching predicate: (WithValue<Value>) -> StateExpr
) -> Expr<SetExpr<Value>> {
  let binding = "__pcal_filtered_value"
  return Expr(.setFilter(
    candidates.raw,
    binding,
    predicate(WithValue<Value>(expression: .variable(binding)))
  ))
}

/// Selects one value from a finite formal domain.
///
/// Use this for a fixed model value, such as a graph supplied by a TLC
/// configuration. The selection is evaluated by the formal evaluator while
/// the spec is built; it is not application control flow.
public func Select<Value: TLAValueType>(
  from candidates: Expr<SetExpr<Value>>,
  matching predicate: (WithValue<Value>) -> StateExpr
) -> Expr<Value> {
  let binding = "__tla_static_choice"
  let choice = StateExpr.choose(
    candidates.raw,
    binding,
    predicate(WithValue<Value>(expression: .variable(binding)))
  )
  guard let value = try? choice.evaluate(in: [:]) else {
    preconditionFailure("Select(from:matching:) requires a non-empty static formal domain")
  }
  return Expr(.value(value))
}

public struct SetExpr<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let values: Set<TLAValue>

  public init() {
    values = []
  }

  public init?(formalValue: TLAValue) {
    guard case .set(let values) = formalValue,
          values.allSatisfy({ Element(formalValue: $0) != nil })
    else { return nil }
    self.values = values
  }

  public var tlaValue: TLAValue { .set(values) }
  public static var defaultValue: Self { Self() }

  /// The typed members of this finite formal set. Their order is unspecified.
  public var elements: [Element] { values.compactMap(Element.init(formalValue:)) }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    Expr(.setLiteral(elements.map { .value($0.tlaValue) }))
  }

  public static func literal(_ elements: Expr<Element>...) -> Expr<Self> {
    Expr(.setLiteral(elements.map(\.raw)))
  }
}

public protocol FormalSetValue: TLAValueType {}
extension SetExpr: FormalSetValue {}

extension Expr where T: FormalSetValue {
  public var isEmpty: StateExpr {
    .equal(.cardinality(raw), .value(.int(0)))
  }

  public var cardinality: Expr<Int> {
    Expr<Int>(.cardinality(raw))
  }

  public func isSubset(of other: some StateExprConvertible) -> StateExpr {
    raw.isSubset(of: other)
  }
}

/// A typed finite TLA+ tuple (sequence).
///
/// This is the formal sequence value, not a Swift `Array`. Use it for ordered
/// state. Its storage is private so application code cannot accidentally make
/// a host-language collection part of the specification.
public struct TupleExpr<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let values: [TLAValue]

  public init() {
    values = []
  }

  public init?(formalValue: TLAValue) {
    guard case .tuple(let values) = formalValue,
          values.allSatisfy({ Element(formalValue: $0) != nil })
    else { return nil }
    self.values = values
  }

  public var tlaValue: TLAValue { .tuple(values) }
  public static var defaultValue: Self { Self() }

  /// The typed tuple elements, in their formal order.
  public var elements: [Element] { values.compactMap(Element.init(formalValue:)) }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    Expr(.tupleLiteral(elements.map { .value($0.tlaValue) }))
  }

  public static func literal(_ elements: Expr<Element>...) -> Expr<Self> {
    Expr(.tupleLiteral(elements.map(\.raw)))
  }
}

public protocol FormalTupleValue: TLAValueType {}
extension TupleExpr: FormalTupleValue {}

/// A typed two-member TLA+ tuple.
///
/// Use `Pair` when the two positions have different formal types. This is a
/// formal tuple, not a Swift tuple: it can be stored in formal state, used as
/// a set member, and selected by a PlusCal `with` binding.
public struct Pair<First: TLAValueType, Second: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let firstValue: TLAValue
  private let secondValue: TLAValue

  public init(first: First = .defaultValue, second: Second = .defaultValue) {
    firstValue = first.tlaValue
    secondValue = second.tlaValue
  }

  public init?(formalValue: TLAValue) {
    guard case .tuple(let values) = formalValue,
          values.count == 2,
          First(formalValue: values[0]) != nil,
          Second(formalValue: values[1]) != nil
    else { return nil }
    firstValue = values[0]
    secondValue = values[1]
  }

  public var tlaValue: TLAValue { .tuple([firstValue, secondValue]) }
  public static var defaultValue: Self { Self() }

  public var first: First {
    guard let value = First(formalValue: firstValue) else {
      preconditionFailure("Pair contains an invalid first value")
    }
    return value
  }

  public var second: Second {
    guard let value = Second(formalValue: secondValue) else {
      preconditionFailure("Pair contains an invalid second value")
    }
    return value
  }

  public static func literal(_ first: First, _ second: Second) -> Expr<Self> {
    Expr(.tupleLiteral([.value(first.tlaValue), .value(second.tlaValue)]))
  }

  public static func literal(_ first: Expr<First>, _ second: Expr<Second>) -> Expr<Self> {
    Expr(.tupleLiteral([first.raw, second.raw]))
  }
}

extension Pair: FormalTupleValue {}

/// A finite formal sequence whose first element is at index zero.
///
/// TLA+ represents this value as a function with domain `0..<(count)`. It is
/// useful for source algorithms that use `ZSequences`; it is not a Swift
/// array or dictionary.
public struct ZeroBasedSequence<Element: TLAValueType>: TLAValueType, Hashable, Sendable {
  private let values: [TLAValue: TLAValue]

  public init() {
    values = [:]
  }

  public init?(formalValue: TLAValue) {
    guard case .function(let values) = formalValue else { return nil }
    let indexes = values.keys.compactMap { value -> Int? in
      guard case .int(let index) = value else { return nil }
      return index
    }
    guard indexes.count == values.count,
          indexes.allSatisfy({ $0 >= 0 }),
          Set(indexes) == Set(0..<indexes.count),
          values.values.allSatisfy({ Element(formalValue: $0) != nil })
    else { return nil }
    self.values = values
  }

  public var tlaValue: TLAValue { .function(values) }
  public static var defaultValue: Self { Self() }

  /// Creates a zero-based formal sequence from values in formal order.
  public static func literal(_ elements: Element...) -> Expr<Self> {
    literal(elements.map { .value($0.tlaValue) })
  }

  public static func literal(_ elements: Expr<Element>...) -> Expr<Self> {
    literal(elements.map(\.raw))
  }

  /// Creates a zero-based formal sequence with the supplied formal length.
  ///
  /// The length and value may depend on earlier formal state. No application
  /// code executes when the sequence is built.
  public static func filled(
    length: Expr<Int>,
    with value: Expr<Element>
  ) -> Expr<Self> {
    let index = "__zeroBasedSequenceIndex"
    return Expr(.functionLiteral(
      .integerRange(.int(0), .subtract(length.raw, .int(1))),
      index,
      value.raw
    ))
  }

  public static func filled(length: Expr<Int>, with value: Element) -> Expr<Self> {
    filled(length: length, with: Expr(.value(value.tlaValue)))
  }

  private static func literal(_ elements: [StateExpr]) -> Expr<Self> {
    let index = "__zeroBasedSequenceIndex"
    let pairs = elements.enumerated().flatMap { offset, element in
      [StateExpr.equal(.variable(index), .int(offset)), element]
    }
    return Expr(.functionLiteral(
      .setLiteral(elements.indices.map { .int($0) }),
      index,
      .caseExpr(pairs, .value(Element.defaultValue.tlaValue))
    ))
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
  of elements: Expr<SetExpr<Element>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<TupleExpr<Element>>> {
  guard case .setLiteral(let members) = elements.raw else {
    preconditionFailure("Sequences(of:lengths:) requires SetExpr.literal(...) as its element domain")
  }

  let sequences = formalSequenceExpressions(members: members, lengths: lengths)
  return Expr<SetExpr<TupleExpr<Element>>>(.setLiteral(sequences))
}

/// Creates a finite formal set of zero-based sequences for model checking.
///
/// This is the bounded form of a `ZSeq(S)` input domain. The returned values
/// have function domains `0..<(length)`, so indexing at zero stays formal.
public func ZeroBasedSequences<Element: TLAValueType>(
  of elements: Expr<SetExpr<Element>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<ZeroBasedSequence<Element>>> {
  guard case .setLiteral(let members) = elements.raw else {
    preconditionFailure("ZeroBasedSequences(of:lengths:) requires SetExpr.literal(...) as its element domain")
  }
  return Expr(.setLiteral(formalZeroBasedSequenceExpressions(members: members, lengths: lengths)))
}

/// Creates a finite formal set of nondecreasing integer sequences.
///
/// This is the bounded model-checking form of a sorted `Seq(Values)` domain.
/// It is useful when the sortedness is an assumption of the algorithm, as in
/// binary search, rather than state that the algorithm itself must establish.
// swiftlint:disable:next identifier_name
public func SortedSequences(
  of elements: Expr<SetExpr<Int>>,
  lengths: ClosedRange<Int>
) -> Expr<SetExpr<TupleExpr<Int>>> {
  guard case .setLiteral(let members) = elements.raw else {
    preconditionFailure("SortedSequences(of:lengths:) requires SetExpr.literal(...) as its element domain")
  }
  return Expr<SetExpr<TupleExpr<Int>>>(.setLiteral(
    formalSequenceExpressions(members: members, lengths: lengths).filter(formalIntegerSequenceIsSorted)
  ))
}

/// The shared finite expansion used by the runtime builder and source parser.
/// Keeping this operation here makes the two construction paths enumerate the
/// same sequence domain without exposing host-language arrays to a model.
func formalSequenceExpressions(
  members: [StateExpr],
  lengths: ClosedRange<Int>
) -> [StateExpr] {
  guard lengths.lowerBound >= 0 else {
    preconditionFailure("Sequences(of:lengths:) does not accept negative lengths")
  }

  var result: [StateExpr] = []
  for length in lengths {
    var prefixes: [[StateExpr]] = [[]]
    for _ in 0..<length {
      prefixes = prefixes.flatMap { prefix in
        members.map { prefix + [$0] }
      }
    }
    result += prefixes.map(StateExpr.tupleLiteral)
  }
  return result
}

func formalZeroBasedSequenceExpressions(
  members: [StateExpr],
  lengths: ClosedRange<Int>
) -> [StateExpr] {
  guard lengths.lowerBound >= 0 else {
    preconditionFailure("ZeroBasedSequences(of:lengths:) does not accept negative lengths")
  }
  return formalSequenceExpressions(members: members, lengths: lengths).map { tuple in
    guard case .tupleLiteral(let elements) = tuple else { return tuple }
    let index = "__zeroBasedSequenceIndex"
    let pairs = elements.enumerated().flatMap { offset, element in
      [StateExpr.equal(.variable(index), .int(offset)), element]
    }
    return .functionLiteral(
      .setLiteral(elements.indices.map { .int($0) }),
      index,
      .caseExpr(pairs, .value(.int(0)))
    )
  }
}

func formalIntegerSequenceIsSorted(_ expression: StateExpr) -> Bool {
  guard case .tupleLiteral(let values) = expression else { return false }
  let integers = values.compactMap { value -> Int? in
    guard case .value(.int(let integer)) = value else { return nil }
    return integer
  }
  return integers.count == values.count
    && zip(integers, integers.dropFirst()).allSatisfy { $0 <= $1 }
}

extension Expr {
  /// Returns the formal union of two typed sets.
  public func union<Element: TLAValueType>(
    _ other: Expr<SetExpr<Element>>
  ) -> Expr<SetExpr<Element>> where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(raw, other.raw))
  }

  public func inserting<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<SetExpr<Element>>
  where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(raw, .setLiteral([element.raw])))
  }

  public func inserting<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
  where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(raw, .setLiteral([.value(element.tlaValue)])))
  }

  public func inserting<Element: FiniteDomainKey>(
    _ element: ProcessIdentifier<Element>
  ) -> Expr<SetExpr<Element>> where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(raw, .setLiteral([element.stateExpr])))
  }

  public func inserting<Element: TLAValueType>(
    _ element: WithValue<Element>
  ) -> Expr<SetExpr<Element>> where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.union(raw, .setLiteral([element.stateExpr])))
  }

  public func removing<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<SetExpr<Element>>
  where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.setDifference(raw, .setLiteral([element.raw])))
  }

  public func removing<Element: TLAValueType>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
  where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.setDifference(raw, .setLiteral([element.stateExpr])))
  }

  public func removing<Element: FiniteDomainKey>(_ element: ProcessIdentifier<Element>) -> Expr<SetExpr<Element>>
  where T == SetExpr<Element> {
    Expr<SetExpr<Element>>(.setDifference(raw, .setLiteral([element.stateExpr])))
  }

  public func contains<Element: TLAValueType>(_ element: Element) -> StateExpr
  where T == SetExpr<Element> {
    .in(.value(element.tlaValue), raw)
  }

  public func contains<Element: TLAValueType>(_ element: Expr<Element>) -> StateExpr
  where T == SetExpr<Element> {
    .in(element.raw, raw)
  }

  /// Tests membership of the current PlusCal process identifier.
  public func contains<Element: FiniteDomainKey>(_ element: ProcessIdentifier<Element>) -> StateExpr
  where T == SetExpr<Element> {
    .in(element.stateExpr, raw)
  }

  /// Tests membership of a value selected by a bounded `With` statement.
  ///
  /// The selected value remains formal data. This avoids leaking the
  /// underlying expression representation into algorithm source.
  public func contains<Element: TLAValueType>(_ element: WithValue<Element>) -> StateExpr
  where T == SetExpr<Element> {
    .in(element.stateExpr, raw)
  }

  public func appending<Element: TLAValueType>(_ element: Element) -> Expr<TupleExpr<Element>>
  where T == TupleExpr<Element> {
    Expr<TupleExpr<Element>>(.tupleAppend(raw, .value(element.tlaValue)))
  }

  public func appending<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<TupleExpr<Element>>
  where T == TupleExpr<Element> {
    Expr<TupleExpr<Element>>(.tupleAppend(raw, element.raw))
  }

  /// Concatenates two formal one-based sequences.
  ///
  /// The right side may be a finite function selected by `CHOOSE`; TLA+
  /// defines that function as a sequence when its domain is `1..n`.
  public func concatenating<Element: TLAValueType>(
    _ other: Expr<TupleExpr<Element>>
  ) -> Expr<TupleExpr<Element>> where T == TupleExpr<Element> {
    Expr<TupleExpr<Element>>(.tupleConcatenate(raw, other.raw))
  }

  public func at<Element: TLAValueType>(_ index: Int) -> Expr<Element> where T == TupleExpr<Element> {
    Expr<Element>(.tupleAccess(raw, index))
  }

  public func first<First: TLAValueType, Second: TLAValueType>() -> Expr<First>
  where T == Pair<First, Second> {
    Expr<First>(.tupleAccess(raw, 1))
  }

  public func second<First: TLAValueType, Second: TLAValueType>() -> Expr<Second>
  where T == Pair<First, Second> {
    Expr<Second>(.tupleAccess(raw, 2))
  }

  /// Reads a formal sequence at a one-based formal index.
  public subscript<Element: TLAValueType>(_ index: Expr<Int>) -> Expr<Element>
  where T == TupleExpr<Element> {
    Expr<Element>(.tupleDynamicAccess(raw, index.raw))
  }

  public subscript<Schema: TLARecordSchema, Value>(_ field: TLAField<Schema, Value>) -> Expr<Value>
  where T == Record<Schema> {
    Expr<Value>(.recordAccess(raw, field.name))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Domain) -> Expr<
    Range
  > where T == Function<Domain, Range> {
    Expr<Range>(.functionApply(raw, finiteDomainIndex(index)))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Expr<Domain>) -> Expr<
    Range
  > where T == Function<Domain, Range> {
    Expr<Range>(.functionApply(raw, index.raw))
  }

  /// Reads a finite function at the current member of a PlusCal process family.
  public subscript<Domain: FiniteDomainKey, Range: TLAValueType>(_ index: ProcessIdentifier<Domain>) -> Expr<
    Range
  > where T == Function<Domain, Range> {
    Expr<Range>(.functionApply(raw, index.stateExpr))
  }

  public func updating<Schema: TLARecordSchema, Value>(
    _ field: TLAField<Schema, Value>, to value: Value
  ) -> Expr<Record<Schema>> where T == Record<Schema> {
    Expr<Record<Schema>>(.except(raw, .value(.string(field.name)), .value(value.tlaValue)))
  }

  public func updating<Schema: TLARecordSchema, Value>(
    _ field: TLAField<Schema, Value>, to value: Expr<Value>
  ) -> Expr<Record<Schema>> where T == Record<Schema> {
    Expr<Record<Schema>>(.except(raw, .value(.string(field.name)), value.raw))
  }

  public func updating<Schema: TLARecordSchema, Value>(
    _ field: TLAField<Schema, Value>, to value: WithValue<Value>
  ) -> Expr<Record<Schema>> where T == Record<Schema> {
    Expr<Record<Schema>>(.except(raw, .value(.string(field.name)), value.stateExpr))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(raw, finiteDomainIndex(index), value.raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: Range
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    updating(index, to: Expr<Range>(.value(value.tlaValue)))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    let selected = self[index]
    return Expr<Function<Domain, Range>>(
      .except(raw, finiteDomainIndex(index), update(selected).raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Expr<Domain>, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(raw, index.raw, value.raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Expr<Domain>, to value: Range
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    updating(index, to: Expr<Range>(.value(value.tlaValue)))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Expr<Domain>, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(
      .except(raw, index.raw, update(Expr<Range>(.functionApply(raw, index.raw))).raw))
  }

  public func updating<Domain: FiniteDomainKey, Range: TLAValueType>(
    _ index: ProcessIdentifier<Domain>, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(raw, index.stateExpr, value.raw))
  }

  public func updating<Domain: FiniteDomainKey, Range: TLAValueType>(
    _ index: ProcessIdentifier<Domain>, to value: Range
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    updating(index, to: Expr<Range>(.value(value.tlaValue)))
  }

  public func updating<Domain: FiniteDomainKey, Range: TLAValueType>(
    _ index: WithValue<Domain>, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(
      .except(raw, index.stateExpr, update(Expr<Range>(.functionApply(raw, index.stateExpr))).raw))
  }
}

/// A bounded, inclusive formal integer set. This is TLA+ `lower..upper`, not
/// a Swift range. Both endpoints can depend on the current formal state.
public func IntRange(
  _ lower: some StateExprConvertible,
  through upper: some StateExprConvertible
) -> Expr<SetExpr<Int>> {
  Expr<SetExpr<Int>>(.integerRange(lower.stateExpr, upper.stateExpr))
}

extension Expr {
  /// Selects formal set members that satisfy `predicate`.
  public func filtering<Element: TLAValueType>(
    _ predicate: (WithValue<Element>) -> StateExpr
  ) -> Expr<SetExpr<Element>> where T == SetExpr<Element> {
    let binding = FreshVarName.fresh()
    let element = WithValue<Element>(expression: .variable(binding))
    return Expr<SetExpr<Element>>(.setFilter(raw, binding, predicate(element)))
  }

  /// Maps every formal set member through a typed formal expression.
  public func mapping<Element: TLAValueType, Result: TLAValueType>(
    _ transform: (WithValue<Element>) -> Expr<Result>
  ) -> Expr<SetExpr<Result>> where T == SetExpr<Element> {
    let binding = FreshVarName.fresh()
    let element = WithValue<Element>(expression: .variable(binding))
    return Expr<SetExpr<Result>>(.setMap(transform(element).raw, binding, raw))
  }
}

extension Expr where T: FormalTupleValue {
  public var count: Expr<Int> {
    Expr<Int>(.tupleLength(raw))
  }
}

/// Combines a formal function with the upstream `Functions.FoldFunction` operator.
///
/// The closure builds a `LAMBDA` in the specification. The upstream operator
/// selects a function-domain member with `CHOOSE`, so use an operation whose
/// result does not depend on that selection order. Import `FunctionsModule.module`
/// into the surrounding specification so TLC receives the upstream operator.
public func Fold<Element: TLAValueType, Result: TLAValueType>(
  _ sequence: Expr<TupleExpr<Element>>,
  startingWith initial: Expr<Result>,
  _ combine: (Expr<Element>, Expr<Result>) -> Expr<Result>
) -> Expr<Result> {
  let elementName = FreshVarName.fresh()
  let resultName = FreshVarName.fresh()
  let element = Expr<Element>(.variable(elementName))
  let accumulated = Expr<Result>(.variable(resultName))
  return Expr<Result>(
    .foldFunction(
      FormalLambda(
        parameters: [elementName, resultName],
        body: combine(element, accumulated).raw
      ),
      initial: initial.raw,
      sequence: sequence.raw
    )
  )
}

/// Starts a formal fold from a concrete formal value.
public func Fold<Element: TLAValueType, Result: TLAValueType>(
  _ sequence: Expr<TupleExpr<Element>>,
  startingWith initial: Result,
  _ combine: (Expr<Element>, Expr<Result>) -> Expr<Result>
) -> Expr<Result> {
  Fold(sequence, startingWith: Expr<Result>(.value(initial.tlaValue)), combine)
}

extension Expr where T: FormalZeroBasedSequenceValue {
  /// The formal number of elements in a zero-based sequence.
  public var count: Expr<Int> {
    Expr<Int>(.cardinality(.domain(raw)))
  }
}

extension Expr where T == Int {
  /// Divides formal integers with TLA+ integer-division semantics.
  public func integerDivided(by divisor: Int) -> Expr<Int> {
    Expr(.integerDivide(raw, .int(divisor)))
  }
}

extension Expr {
  /// Reads a formal sequence at a one-based formal index.
  public func at<Element: TLAValueType>(_ index: Expr<Int>) -> Expr<Element>
  where T == TupleExpr<Element> {
    Expr<Element>(.tupleDynamicAccess(raw, index.raw))
  }

  /// Reads a zero-based formal sequence at a formal index.
  public subscript<Element: TLAValueType>(_ index: Expr<Int>) -> Expr<Element>
  where T == ZeroBasedSequence<Element> {
    Expr<Element>(.functionApply(raw, index.raw))
  }

  public subscript<Element: TLAValueType>(_ index: Int) -> Expr<Element>
  where T == ZeroBasedSequence<Element> {
    Expr<Element>(.functionApply(raw, .int(index)))
  }

  /// Replaces one value in a zero-based formal sequence.
  public func updating<Element: TLAValueType>(
    _ index: Expr<Int>,
    to value: Expr<Element>
  ) -> Expr<ZeroBasedSequence<Element>> where T == ZeroBasedSequence<Element> {
    Expr(.except(raw, index.raw, value.raw))
  }

  public func updating<Element: TLAValueType>(
    _ index: Int,
    to value: Expr<Element>
  ) -> Expr<ZeroBasedSequence<Element>> where T == ZeroBasedSequence<Element> {
    Expr(.except(raw, .int(index), value.raw))
  }
}

extension Var {
  public subscript<Schema: TLARecordSchema, Value>(_ field: TLAField<Schema, Value>) -> Expr<Value>
  where T == Record<Schema> {
    Expr<Value>(.recordAccess(stateExpr, field.name))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Domain) -> Expr<
    Range
  > where T == Function<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, finiteDomainIndex(index)))
  }

  public subscript<Domain: FiniteTLAValueDomain, Range: TLAValueType>(_ index: Expr<Domain>) -> Expr<
    Range
  > where T == Function<Domain, Range> {
    Expr<Range>(.functionApply(stateExpr, index.raw))
  }

  public func updating<Schema: TLARecordSchema, Value>(
    _ field: TLAField<Schema, Value>, to value: Value
  ) -> Expr<Record<Schema>> where T == Record<Schema> {
    Expr<Record<Schema>>(.except(stateExpr, .value(.string(field.name)), .value(value.tlaValue)))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(stateExpr, finiteDomainIndex(index), value.raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    let selected = self[index]
    return Expr<Function<Domain, Range>>(
      .except(stateExpr, finiteDomainIndex(index), update(selected).raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Expr<Domain>, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(stateExpr, index.raw, value.raw))
  }

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Expr<Domain>, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(
      .except(stateExpr, index.raw, update(Expr<Range>(.functionApply(stateExpr, index.raw))).raw))
  }

  public func inserting<Element: TLAValueType>(_ element: Element) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(name, .union(stateExpr, .setLiteral([.value(element.tlaValue)])))
  }

  public func inserting<Element: TLAValueType>(_ element: Expr<Element>) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(name, .union(stateExpr, .setLiteral([element.raw])))
  }

  public func removing<Element: TLAValueType>(_ element: Element) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(name, .setDifference(stateExpr, .setLiteral([.value(element.tlaValue)])))
  }

  public func removing<Element: TLAValueType>(_ element: Expr<Element>) -> ActionExpr
  where T == SetExpr<Element> {
    .assign(name, .setDifference(stateExpr, .setLiteral([element.raw])))
  }

  public func contains<Element: TLAValueType>(_ element: Element) -> StateExpr
  where T == SetExpr<Element> {
    .in(.value(element.tlaValue), stateExpr)
  }

  public func contains<Element: TLAValueType>(_ element: Expr<Element>) -> StateExpr
  where T == SetExpr<Element> {
    .in(element.raw, stateExpr)
  }
}

private func finiteDomainIndex<Domain: FiniteTLAValueDomain>(_ index: Domain) -> StateExpr {
  let value = index.tlaValue
  precondition(
    Domain.tlaValues.contains(value), "\(value) is not declared by \(Domain.self).finiteValues")
  return .value(value)
}

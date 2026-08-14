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
  static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String?
}

public struct TLAField<Schema: TLARecordSchema, Value: TLAValueType>: Sendable {
  let name: String
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
}

public struct Record<Schema: TLARecordSchema>: TLAValueType, Sendable {
  public init() {}

  public var tlaValue: TLAValue { .record([:]) }
  public static var defaultValue: Self { Self() }

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

public struct Function<Domain: FiniteTLAValueDomain, Range: TLAValueType>: TLAValueType, Sendable {
  public init() {}

  public var tlaValue: TLAValue { .function([:]) }
  public static var defaultValue: Self { Self() }

  public static func literal(_ entries: (Domain, Expr<Range>)...) -> Expr<Self> {
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

public struct SetExpr<Element: TLAValueType>: TLAValueType, Sendable {
  public init() {}

  public var tlaValue: TLAValue { .set([]) }
  public static var defaultValue: Self { Self() }

  public static func literal(_ elements: Element...) -> Expr<Self> {
    Expr(.setLiteral(elements.map { .value($0.tlaValue) }))
  }

  public static func literal(_ elements: Expr<Element>...) -> Expr<Self> {
    Expr(.setLiteral(elements.map(\.raw)))
  }
}

extension Expr {
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

  public func updating<Domain: FiniteTLAValueDomain, Range: TLAValueType>(
    _ index: Domain, to value: Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(.except(raw, finiteDomainIndex(index), value.raw))
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
    _ index: Expr<Domain>, _ update: (Expr<Range>) -> Expr<Range>
  ) -> Expr<Function<Domain, Range>> where T == Function<Domain, Range> {
    Expr<Function<Domain, Range>>(
      .except(raw, index.raw, update(Expr<Range>(.functionApply(raw, index.raw))).raw))
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

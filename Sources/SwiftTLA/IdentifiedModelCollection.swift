/// Runtime storage for a symmetric verification collection.
///
/// Its keys are application identities, which deliberately never enter the
/// verification AST or the generated model-value domain.
public struct SymmetricCollectionProjection<ID: Hashable> {
  public let modelValue: TLAValue
  private let keys: [ID: TLAValue]
  private let values: [ID: TLAValue]

  init(modelValue: TLAValue, keys: [ID: TLAValue], values: [ID: TLAValue]) {
    self.modelValue = modelValue
    self.keys = keys
    self.values = values
  }

  public func key(for id: ID, collection: String, action: String) throws -> TLAValue {
    guard let key = keys[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: collection, action: action)
    }
    return key
  }

  public func value(for id: ID, collection: String, action: String) throws -> TLAValue {
    guard let value = values[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: collection, action: action)
    }
    return value
  }
}

public struct IdentifiedModelCollection<Element: Identifiable, Value: TLAValueType> {
  public struct Entry {
    public let element: Element
    public var value: Value

    public init(element: Element, value: Value) {
      self.element = element
      self.value = value
    }
  }

  public let name: String
  public let verificationScope: Int
  private var entries: [Element.ID: Entry] = [:]
  private var insertionOrder: [Element.ID] = []

  public init(name: String, verificationScope: Int, initial: Value) {
    precondition(verificationScope > 0, "A symmetric collection requires a positive verification scope")
    self.name = name
    self.verificationScope = verificationScope
    self.initial = initial
  }

  private let initial: Value

  public var count: Int { entries.count }

  public subscript(id: Element.ID) -> Value? {
    entries[id]?.value
  }

  public mutating func insert(_ element: Element, value: Value? = nil) {
    if entries[element.id] == nil {
      insertionOrder.append(element.id)
    }
    entries[element.id] = Entry(element: element, value: value ?? initial)
  }

  @discardableResult
  public mutating func remove(id: Element.ID) -> Entry? {
    let removed = entries.removeValue(forKey: id)
    if removed != nil {
      insertionOrder.removeAll { $0 == id }
    }
    return removed
  }

  public mutating func update(id: Element.ID, to value: Value, action: String) throws {
    guard var entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name, action: action)
    }
    entry.value = value
    entries[id] = entry
  }

  public mutating func update(
    id: Element.ID,
    action: String,
    transforming transform: (Entry) -> Value
  ) throws {
    guard var entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name, action: action)
    }
    entry.value = transform(entry)
    entries[id] = entry
  }

  public func entry(for id: Element.ID, action: String) throws -> Entry {
    guard let entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name, action: action)
    }
    return entry
  }

  public func projection() -> SymmetricCollectionProjection<Element.ID> {
    let pairs = insertionOrder.enumerated().compactMap { index, id -> (Element.ID, TLAValue, TLAValue)? in
      guard let entry = entries[id] else { return nil }
      return (id, .constant("\(name)LiveMember\(index)"), entry.value.tlaValue)
    }
    return .init(
      modelValue: .function(Dictionary(uniqueKeysWithValues: pairs.map { ($0.1, $0.2) })),
      keys: Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) }),
      values: Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.2) })
    )
  }

  public func projectedModelValue(preserving modelKeys: [TLAValue]) -> TLAValue {
    let projection = projection()
    let entries = insertionOrder.enumerated().compactMap { index, id -> (TLAValue, TLAValue)? in
      guard let value = try? projection.value(for: id, collection: name, action: "projection") else { return nil }
      let key = modelKeys.indices.contains(index) ? modelKeys[index] : .constant("\(name)LiveMember\(index)")
      return (key, value)
    }
    return .function(Dictionary(uniqueKeysWithValues: entries))
  }
}

extension IdentifiedModelCollection.Entry: Sendable where Element: Sendable, Value: Sendable {}

extension IdentifiedModelCollection: Sendable where Element: Sendable, Element.ID: Sendable, Value: Sendable {}

public enum SymmetricCollectionRuntimeError: Error, Equatable, CustomStringConvertible {
  case unknownMember(collection: String, action: String)
  case actionNotEnabled(collection: String, action: String)

  public var description: String {
    switch self {
    case .unknownMember(let collection, let action):
      return "Symmetric collection '\(collection)' cannot route action '\(action)' to an unknown runtime member."
    case .actionNotEnabled(let collection, let action):
      return "Symmetric collection '\(collection)' cannot apply action '\(action)' to the selected runtime member in its current state."
    }
  }
}

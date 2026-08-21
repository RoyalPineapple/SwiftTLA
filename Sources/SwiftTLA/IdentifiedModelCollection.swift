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

  public init(name: String, verificationScope: Int, initial: Value) throws {
    guard verificationScope > 0 else {
      throw SymmetricCollectionRuntimeError.invalidVerificationScope(
        collection: name,
        scope: verificationScope
      )
    }
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

  public mutating func update(id: Element.ID, to value: Value) throws {
    guard var entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name)
    }
    entry.value = value
    entries[id] = entry
  }

  public mutating func update(
    id: Element.ID,
    transforming transform: (Entry) -> Value
  ) throws {
    guard var entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name)
    }
    entry.value = transform(entry)
    entries[id] = entry
  }

  public func entry(for id: Element.ID) throws -> Entry {
    guard let entry = entries[id] else {
      throw SymmetricCollectionRuntimeError.unknownMember(collection: name)
    }
    return entry
  }

  public func projectedModelValue(preserving modelKeys: [TLAValue]) -> TLAValue {
    let entries = insertionOrder.enumerated().compactMap { index, id -> (TLAValue, TLAValue)? in
      guard let entry = self.entries[id] else { return nil }
      let key = modelKeys.indices.contains(index) ? modelKeys[index] : .constant("\(name)LiveMember\(index)")
      return (key, entry.value.tlaValue)
    }
    return .function(Dictionary(uniqueKeysWithValues: entries))
  }
}

extension IdentifiedModelCollection.Entry: Sendable where Element: Sendable, Value: Sendable {}

extension IdentifiedModelCollection: Sendable where Element: Sendable, Element.ID: Sendable, Value: Sendable {}

public enum SymmetricCollectionRuntimeError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidVerificationScope(collection: String, scope: Int)
  case unknownMember(collection: String)

  public var description: String {
    switch self {
    case .invalidVerificationScope(let collection, let scope):
      return "Symmetric collection '\(collection)' requires a positive verification scope; received \(scope)."
    case .unknownMember(let collection):
      return "Symmetric collection '\(collection)' cannot update an unknown runtime member."
    }
  }
}

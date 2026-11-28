/// Mutable function storage shared by standard and generated native dictionaries.
@_documentation(visibility: internal)
public protocol _NativeFunctionStorage {
    associatedtype Key
    associatedtype Value
    init()
    @discardableResult
    mutating func updateValue(_ value: Value, forKey key: Key) -> Value?
}

extension Dictionary: _NativeFunctionStorage {}

/// A typed dictionary whose key and value identity come from resolved compiler fields.
@_documentation(visibility: internal)
public struct _NativeDictionary<KeyIdentity: _NativeSetIdentity, ValueIdentity: _NativeSetIdentity>:
    Hashable, Sendable, Sequence, ExpressibleByDictionaryLiteral, _NativeFunctionStorage {
    public typealias Key = KeyIdentity.Element
    public typealias Value = ValueIdentity.Element
    public typealias Element = (key: Key, value: Value)

    private typealias StoredKey = _NativeIdentityKey<KeyIdentity>
    private var storage: [StoredKey: Value]

    public init() { storage = [:] }
    public init<S: Sequence>(uniqueKeysWithValues entries: S) where S.Element == (Key, Value) {
        storage = Dictionary(uniqueKeysWithValues: entries.map { (StoredKey(value: $0.0), $0.1) })
    }
    public init(dictionaryLiteral elements: (Key, Value)...) {
        storage = [:]
        for (key, value) in elements { updateValue(value, forKey: key) }
    }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var keys: _NativeSet<KeyIdentity> { _NativeSet(storage.keys.map(\.value)) }
    public var values: [Value] { Array(storage.values) }
    public subscript(key: Key) -> Value? {
        get { storage[StoredKey(value: key)] }
        set { storage[StoredKey(value: key)] = newValue }
    }
    @discardableResult
    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        storage.updateValue(value, forKey: StoredKey(value: key))
    }
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        storage.removeValue(forKey: StoredKey(value: key))
    }
    public struct Iterator: IteratorProtocol, Sequence, Sendable {
        private var base: Dictionary<StoredKey, Value>.Iterator

        fileprivate init(_ dictionary: _NativeDictionary) {
            base = dictionary.storage.makeIterator()
        }

        public mutating func next() -> _NativeDictionary.Element? {
            guard let entry = base.next() else { return nil }
            return (entry.key.value, entry.value)
        }
    }

    public func makeIterator() -> Iterator { Iterator(self) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs.storage {
            guard let other = rhs.storage[key], ValueIdentity.equal(value, other) else { return false }
        }
        return true
    }
    public func hash(into hasher: inout Hasher) {
        var unordered = 0
        for (key, value) in storage {
            var entryHasher = Hasher()
            KeyIdentity.hash(key.value, into: &entryHasher)
            ValueIdentity.hash(value, into: &entryHasher)
            unordered ^= entryHasher.finalize()
        }
        hasher.combine(count)
        hasher.combine(unordered)
    }
}

extension _NativeDictionary: TLAValueType, TLAValueConvertible, TypedExpression, StateExprConvertible
where KeyIdentity.Element: TLAValueType, ValueIdentity.Element: TLAValueType {
    public static var defaultValue: Self { [:] }
    public static var formalValueShape: FormalValueShape {
        .function(key: Key.formalValueShape, value: Value.formalValueShape)
    }

    public var sourceIssue: SourceModelIssue? {
        for (key, value) in self {
            if let issue = key.sourceIssue ?? value.sourceIssue { return issue }
        }
        guard Set(keys.map(\.tlaValue)).count == count else {
            return .formalDeclaration(kind: "dictionary", name: nil,
                problem: "distinct Swift keys have the same formal value")
        }
        return nil
    }

    public var tlaValue: TLAValue {
        .function(reduce(into: [:]) { $0[$1.key.tlaValue] = $1.value.tlaValue })
    }

    public init?(formalValue: TLAValue) {
        guard case .function(let entries) = formalValue else { return nil }
        self.init()
        for (rawKey, rawValue) in entries {
            guard let key = Key(formalValue: rawKey), key.preservesFormalValue(rawKey),
                  let value = Value(formalValue: rawValue), value.preservesFormalValue(rawValue),
                  updateValue(value, forKey: key) == nil else { return nil }
        }
    }
}

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

    private struct StoredKey: Hashable, Sendable {
        let value: Key
        static func == (lhs: Self, rhs: Self) -> Bool { KeyIdentity.equal(lhs.value, rhs.value) }
        func hash(into hasher: inout Hasher) { KeyIdentity.hash(value, into: &hasher) }
    }
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
    public func makeIterator() -> IndexingIterator<[Element]> {
        storage.map { (key: $0.key.value, value: $0.value) }.makeIterator()
    }
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

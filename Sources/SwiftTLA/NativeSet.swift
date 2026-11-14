/// Field identity supplied by the compiler for generated native collections.
@_documentation(visibility: internal)
public protocol _NativeSetIdentity: Sendable {
    associatedtype Element: Sendable
    static func equal(_ lhs: Element, _ rhs: Element) -> Bool
    static func hash(_ value: Element, into hasher: inout Hasher)
}

/// Typed set storage that does not consult source-defined equality or hashing.
@_documentation(visibility: internal)
public struct _NativeSet<Identity: _NativeSetIdentity>: Hashable, Sendable,
    RandomAccessCollection, SetAlgebra, ExpressibleByArrayLiteral {
    public typealias Element = Identity.Element
    private var elements: [Element]

    public init() { elements = [] }
    public init<S: Sequence>(_ values: S) where S.Element == Element {
        elements = []
        for value in values { insert(value) }
    }
    public init(arrayLiteral elements: Element...) { self.init(elements) }

    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public func index(after index: Int) -> Int { elements.index(after: index) }
    public func index(before index: Int) -> Int { elements.index(before: index) }
    public subscript(index: Int) -> Element { elements[index] }
    public var isEmpty: Bool { elements.isEmpty }
    public var count: Int { elements.count }

    public func contains(_ member: Element) -> Bool {
        elements.contains { Identity.equal($0, member) }
    }
    @discardableResult
    public mutating func insert(_ member: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        if let old = elements.first(where: { Identity.equal($0, member) }) { return (false, old) }
        elements.append(member)
        return (true, member)
    }
    @discardableResult
    public mutating func update(with member: Element) -> Element? {
        guard let index = elements.firstIndex(where: { Identity.equal($0, member) }) else {
            elements.append(member)
            return nil
        }
        let old = elements[index]
        elements[index] = member
        return old
    }
    @discardableResult
    public mutating func remove(_ member: Element) -> Element? {
        guard let index = elements.firstIndex(where: { Identity.equal($0, member) }) else { return nil }
        return elements.remove(at: index)
    }
    public func union(_ other: Self) -> Self { Self(elements + other.elements) }
    public func intersection(_ other: Self) -> Self { Self(elements.filter(other.contains)) }
    public func symmetricDifference(_ other: Self) -> Self {
        Self(elements.filter { !other.contains($0) } + other.elements.filter { !contains($0) })
    }
    public mutating func formUnion(_ other: Self) { self = union(other) }
    public mutating func formIntersection(_ other: Self) { self = intersection(other) }
    public mutating func formSymmetricDifference(_ other: Self) { self = symmetricDifference(other) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.count == rhs.count && lhs.elements.allSatisfy(rhs.contains)
    }
    public func hash(into hasher: inout Hasher) {
        var unordered = 0
        for member in elements {
            var memberHasher = Hasher()
            Identity.hash(member, into: &memberHasher)
            unordered ^= memberHasher.finalize()
        }
        hasher.combine(count)
        hasher.combine(unordered)
    }
    // shortcut: membership scans resolved values; use compiler-keyed buckets if profiling warrants them.
}

public struct FiniteMap<Key: FiniteDomainKey, Value: FormalValue>: Hashable, Sendable {
    public let keys: [Key]
    public let values: [Key: Value]

    public init(values: [Key: Value]) throws {
        try self.init(domain: Key.formalDomain, values: values)
    }

    public init(domain: [Key], values: [Key: Value]) throws {
        guard !domain.isEmpty else {
            throw FormalShapeValidationError.emptyFiniteDomain
        }
        guard Set(domain).count == domain.count else {
            throw FormalShapeValidationError.duplicateFiniteDomainMember
        }
        guard Set(domain) == Set(values.keys) else {
            throw FormalShapeValidationError.incompleteFiniteMap
        }
        self.keys = domain
        self.values = values
    }

    public subscript(key: Key) -> Value {
        values[key]!
    }

    public static func == (lhs: FiniteMap<Key, Value>, rhs: FiniteMap<Key, Value>) -> Bool {
        lhs.keys == rhs.keys && lhs.keys.allSatisfy { lhs.values[$0] == rhs.values[$0] }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine("FiniteMap.v1")
        hasher.combine(keys.count)
        for key in keys {
            hasher.combine(key)
            hasher.combine(values[key]!)
        }
    }
}

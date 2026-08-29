public struct TLARecord: Hashable, Sendable {
    public struct Field: Hashable, Sendable {
        public let name: String
        public let value: TLAValue

        public init(_ name: String, _ value: TLAValue) {
            self.name = name
            self.value = value
        }
    }

    public let fields: [Field]

    public init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.name < $1.name }
    }

    public func value(named name: String) -> TLAValue? {
        fields.first { $0.name == name }?.value
    }

    package func replacing(_ value: TLAValue, for name: String) -> TLARecord {
        var replaced = false
        let updated = fields.map { field -> Field in
            guard field.name == name else { return field }
            replaced = true
            return .init(name, value)
        }
        return TLARecord(replaced ? updated : updated + [.init(name, value)])
    }
}

extension TLARecord: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, TLAValue)...) {
        self.init(elements.map { .init($0.0, $0.1) })
    }
}

public enum TLAValue: Hashable, Sendable, CustomStringConvertible {
    case int(Int)
    case bool(Bool)
    case string(String)
    case set(Set<TLAValue>)
    case tuple([TLAValue])
    case record(TLARecord)
    case function([TLAValue: TLAValue])
    case constant(String)

    public var description: String { _tlaForm() }

    private func _tlaForm(_ depth: Int = 0) -> String {
        let xs = "__tla_fn_\(depth)"
        switch self {
        case .int(let n): return "\(n)"
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .string(let s): return "\"\(s)\""
        case .set(let s):
            return "{\(s.map { $0._tlaForm(depth) }.sorted().joined(separator: ", "))}"
        case .tuple(let t):
            return "<<\(t.map { $0._tlaForm(depth) }.joined(separator: ", "))>>"
        case .record(let r):
            let fields = r.fields.map { "\($0.name) |-> \($0.value._tlaForm(depth))" }
            return "[\(fields.joined(separator: ", "))]"
        case .function(let mapping):
            let sorted = mapping.sorted(by: { $0.key < $1.key })
            let innerDepth = depth + 1
            if sorted.isEmpty { return "[\(xs) \\in {} |-> TRUE]" }
            let values = Set(sorted.map(\.value))
            if values.count == 1, let v = values.first {
                let domain = "{\(sorted.map { "\($0.key._tlaForm(innerDepth))" }.joined(separator: ", "))}"
                return "[\(xs) \\in \(domain) |-> \(v._tlaForm(innerDepth))]"
            }
            let domain = "{\(sorted.map { "\($0.key._tlaForm(innerDepth))" }.joined(separator: ", "))}"
            let body = sorted.map { "(\(xs) = \($0.key._tlaForm(innerDepth))) -> \($0.value._tlaForm(innerDepth))" }.joined(separator: " [] ")
            return "[\(xs) \\in \(domain) |-> CASE \(body)]"

        case .constant(let name): return name
        }
    }
}

public enum TLAValueCodingError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case unknownTag(String)
    case malformedValue(String)
}

extension TLAValue: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case tag
        case value
        case elements
        case fields
        case mappings
    }

    private enum Tag: String {
        case int
        case bool
        case string
        case set
        case tuple
        case record
        case function
        case constant
    }

    private struct DynamicCodingKey: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private struct RecordEntry: Codable {
        let key: String
        let value: TLAValue
    }

    private struct FunctionEntry: Codable {
        let key: TLAValue
        let value: TLAValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.version), container.contains(.tag) else {
            throw TLAValueCodingError.malformedValue("value")
        }
        guard let version = try? container.decode(Int.self, forKey: .version) else {
            throw TLAValueCodingError.malformedValue("value")
        }
        guard version == 1 else {
            throw TLAValueCodingError.unsupportedVersion(version)
        }
        guard let tagName = try? container.decode(String.self, forKey: .tag), let tag = Tag(rawValue: tagName) else {
            let tagName = (try? container.decode(String.self, forKey: .tag)) ?? ""
            throw TLAValueCodingError.unknownTag(tagName)
        }

        switch tag {
        case .int:
            try Self.requireKeys([.version, .tag, .value], from: decoder, for: tag)
            guard let value = try? container.decode(Int.self, forKey: .value) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .int(value)
        case .bool:
            try Self.requireKeys([.version, .tag, .value], from: decoder, for: tag)
            guard let value = try? container.decode(Bool.self, forKey: .value) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .bool(value)
        case .string:
            try Self.requireKeys([.version, .tag, .value], from: decoder, for: tag)
            guard let value = try? container.decode(String.self, forKey: .value) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .string(value)
        case .constant:
            try Self.requireKeys([.version, .tag, .value], from: decoder, for: tag)
            guard let value = try? container.decode(String.self, forKey: .value) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .constant(value)
        case .set:
            try Self.requireKeys([.version, .tag, .elements], from: decoder, for: tag)
            guard let elements = try? container.decode([TLAValue].self, forKey: .elements) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .set(Set(elements))
        case .tuple:
            try Self.requireKeys([.version, .tag, .elements], from: decoder, for: tag)
            guard let elements = try? container.decode([TLAValue].self, forKey: .elements) else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .tuple(elements)
        case .record:
            try Self.requireKeys([.version, .tag, .fields], from: decoder, for: tag)
            guard let fields = try? container.decode([RecordEntry].self, forKey: .fields), Set(fields.map(\.key)).count == fields.count else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .record(TLARecord(fields.map { .init($0.key, $0.value) }))
        case .function:
            try Self.requireKeys([.version, .tag, .mappings], from: decoder, for: tag)
            guard let mappings = try? container.decode([FunctionEntry].self, forKey: .mappings),
                  Set(mappings.map(\.key)).count == mappings.count else {
                throw TLAValueCodingError.malformedValue(tag.rawValue)
            }
            self = .function(Dictionary(uniqueKeysWithValues: mappings.map { ($0.key, $0.value) }))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)

        switch self {
        case .int(let value):
            try container.encode(Tag.int.rawValue, forKey: .tag)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(Tag.bool.rawValue, forKey: .tag)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(Tag.string.rawValue, forKey: .tag)
            try container.encode(value, forKey: .value)
        case .set(let elements):
            try container.encode(Tag.set.rawValue, forKey: .tag)
            try container.encode(Array(elements), forKey: .elements)
        case .tuple(let elements):
            try container.encode(Tag.tuple.rawValue, forKey: .tag)
            try container.encode(elements, forKey: .elements)
        case .record(let fields):
            try container.encode(Tag.record.rawValue, forKey: .tag)
            try container.encode(fields.fields.map { RecordEntry(key: $0.name, value: $0.value) }, forKey: .fields)
        case .function(let mappings):
            try container.encode(Tag.function.rawValue, forKey: .tag)
            try container.encode(mappings.map { FunctionEntry(key: $0.key, value: $0.value) }, forKey: .mappings)
        case .constant(let value):
            try container.encode(Tag.constant.rawValue, forKey: .tag)
            try container.encode(value, forKey: .value)
        }
    }

    private static func requireKeys(_ expected: Set<CodingKeys>, from decoder: Decoder, for tag: Tag) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(expected.map(\.rawValue)) else {
            throw TLAValueCodingError.malformedValue(tag.rawValue)
        }
    }
}

extension TLAValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension TLAValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension TLAValue: Comparable {
    public static func < (lhs: TLAValue, rhs: TLAValue) -> Bool {
        guard lhs.orderingKind == rhs.orderingKind else {
            return lhs.orderingKind < rhs.orderingKind
        }

        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a < b
        case (.bool(let a), .bool(let b)): return (a ? 1 : 0) < (b ? 1 : 0)
        case (.string(let a), .string(let b)): return a < b
        case (.set(let a), .set(let b)):
            return a.sorted().lexicographicallyPrecedes(b.sorted())
        case (.tuple(let a), .tuple(let b)):
            return a.lexicographicallyPrecedes(b)
        case (.record(let a), .record(let b)):
            return recordFields(a.fields, precede: b.fields)
        case (.function(let a), .function(let b)):
            return functionEntries(a, precede: b)
        case (.constant(let a), .constant(let b)): return a < b
        default: return false
        }
    }

    private var orderingKind: Int {
        switch self {
        case .int: 0
        case .bool: 1
        case .string: 2
        case .set: 3
        case .tuple: 4
        case .record: 5
        case .function: 6
        case .constant: 7
        }
    }

    private static func recordFields(
        _ lhs: [TLARecord.Field],
        precede rhs: [TLARecord.Field]
    ) -> Bool {
        for (left, right) in zip(lhs, rhs) {
            if (left.name == right.name) == false { return left.name < right.name }
            if (left.value == right.value) == false { return left.value < right.value }
        }
        return lhs.count < rhs.count
    }

    private static func functionEntries(
        _ lhs: [TLAValue: TLAValue],
        precede rhs: [TLAValue: TLAValue]
    ) -> Bool {
        let leftKeys = lhs.keys.sorted()
        let rightKeys = rhs.keys.sorted()
        for (leftKey, rightKey) in zip(leftKeys, rightKeys) {
            if (leftKey == rightKey) == false { return leftKey < rightKey }
            guard let leftValue = lhs[leftKey], let rightValue = rhs[rightKey] else {
                return leftKeys.count < rightKeys.count
            }
            if (leftValue == rightValue) == false { return leftValue < rightValue }
        }
        return leftKeys.count < rightKeys.count
    }

}

extension TLAValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

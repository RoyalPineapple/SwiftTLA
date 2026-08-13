public enum TLAValue: Hashable, Sendable, CustomStringConvertible {
    case int(Int)
    case bool(Bool)
    case string(String)
    case set(Set<TLAValue>)
    case tuple([TLAValue])
    case record([String: TLAValue])
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
            let fields = r.sorted(by: { $0.key < $1.key }).map { "\($0.key) |-> \($0.value._tlaForm(depth))" }
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
            self = .record(Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) }))
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
            try container.encode(fields.keys.sorted().map { RecordEntry(key: $0, value: fields[$0]!) }, forKey: .fields)
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

public func set(_ elements: [some TLAValueConvertible]) -> TLAValue {
    .set(Set(elements.map(\.tlaValue)))
}

public func tuple(_ elements: [some TLAValueConvertible]) -> TLAValue {
    .tuple(elements.map(\.tlaValue))
}

public func record(_ fields: [String: TLAValue]) -> TLAValue {
    .record(fields)
}

extension TLAValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension TLAValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension TLAValue {
    public var intValue: Int { if case .int(let n) = self { return n }; return 0 }
    public var boolValue: Bool { if case .bool(let b) = self { return b }; return false }
    public var stringValue: String { if case .string(let s) = self { return s }; return "" }
    public var setValue: Set<TLAValue> { if case .set(let s) = self { return s }; return [] }
    public var intSetValue: Set<Int> { Set(setValue.compactMap { if case .int(let n) = $0 { return n }; return nil }) }
    public var tupleValue: [TLAValue] { if case .tuple(let t) = self { return t }; return [] }
    public var recordValue: [String: TLAValue] { if case .record(let r) = self { return r }; return [:] }
    public var functionValue: [TLAValue: TLAValue] { if case .function(let f) = self { return f }; return [:] }
}

extension TLAValue: Comparable {
    public static func < (lhs: TLAValue, rhs: TLAValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a < b
        case (.int, _): return false
        case (_, .int): return true
        case (.bool(let a), .bool(let b)): return (a ? 1 : 0) < (b ? 1 : 0)
        case (.bool, _): return false
        case (_, .bool): return true
        case (.string(let a), .string(let b)): return a < b
        case (.string, _): return false
        case (_, .string): return true
        case (.set(let a), .set(let b)): return a.count < b.count
        case (.set, _): return false
        case (_, .set): return true
        case (.tuple(let a), .tuple(let b)): return a.count < b.count
        case (.tuple, _): return false
        case (_, .tuple): return true
        case (.record(let a), .record(let b)): return a.count < b.count
        case (.record, _): return false
        case (_, .record): return true
        case (.function(let a), .function(let b)): return a.count < b.count
        case (.function, _): return false
        case (_, .function): return true
        case (.constant(let a), .constant(let b)): return a < b
        }
    }

    public static func sorted(_ values: Set<TLAValue>) -> [TLAValue] {
        Array(values).sorted()
    }

    public static func functionSet(domain: Set<TLAValue>, range: Set<TLAValue>) -> Set<TLAValue> {
        let domainArr = domain.sorted()
        let rangeArr = range.sorted()
        var result = Set<TLAValue>()
        func build(_ idx: Int, _ cur: [(TLAValue, TLAValue)]) {
            if idx == domainArr.count {
                result.insert(.function(Dictionary(uniqueKeysWithValues: cur)))
                return
            }
            for r in rangeArr {
                build(idx + 1, cur + [(domainArr[idx], r)])
            }
        }
        if !domainArr.isEmpty { build(0, []) } else { result.insert(.function([:])) }
        return result
    }
}

extension TLAValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

// MARK: - Arithmetic operators

extension TLAValue {
    public static func + (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a + b)
        case (.tuple(let a), .tuple(let b)): return .tuple(a + b)
        case (.tuple(let a), _): return .tuple(a + [rhs])
        case (_, .tuple(let b)): return .tuple([lhs] + b)
        default: return .int(0)
        }
    }

    public static func - (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a - b)
        default: return .int(0)
        }
    }

    public static func * (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a * b)
        default: return .int(0)
        }
    }

    public static func / (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return b != 0 ? .int(a / b) : .int(0)
        default: return .int(0)
        }
    }

    public static func % (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return b != 0 ? .int(a % b) : .int(0)
        default: return .int(0)
        }
    }

    public static prefix func - (operand: TLAValue) -> TLAValue {
        switch operand {
        case .int(let n): return .int(-n)
        default: return .int(0)
        }
    }
}

// MARK: - Logical operators

extension TLAValue {
    public static func && (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.bool(let a), .bool(let b)): return .bool(a && b)
        default: return .bool(false)
        }
    }

    public static func || (lhs: TLAValue, rhs: TLAValue) -> TLAValue {
        switch (lhs, rhs) {
        case (.bool(let a), .bool(let b)): return .bool(a || b)
        default: return .bool(false)
        }
    }

    public static prefix func ! (operand: TLAValue) -> TLAValue {
        switch operand {
        case .bool(let b): return .bool(!b)
        default: return .bool(false)
        }
    }
}

// MARK: - Conditional

extension TLAValue {
    public static func ternary(condition: TLAValue, then: TLAValue, else elseValue: TLAValue) -> TLAValue {
        switch condition {
        case .bool(let b): return b ? then : elseValue
        default: return elseValue
        }
    }
}

// MARK: - Collection methods

extension TLAValue {
    public var cardinality: TLAValue {
        switch self {
        case .set(let s): return .int(s.count)
        case .function(let f): return .int(f.count)
        case .tuple(let t): return .int(t.count)
        default: return .int(0)
        }
    }

    public var keys: TLAValue {
        switch self {
        case .function(let f): return .set(Set(f.keys))
        case .record(let r): return .set(Set(r.keys.map { .string($0) }))
        default: return .set([])
        }
    }

    public var powerSet: TLAValue {
        guard case .set(let s) = self else { return .set([]) }
        let arr = Array(s)
        var result = Set<TLAValue>()
        let n = arr.count
        for mask in 0..<(1 << n) {
            var subset = Set<TLAValue>()
            for i in 0..<n where (mask >> i) & 1 == 1 {
                subset.insert(arr[i])
            }
            result.insert(.set(subset))
        }
        return .set(result)
    }

    public var flattened: TLAValue {
        guard case .set(let s) = self else { return .set([]) }
        var result = Set<TLAValue>()
        for elem in s {
            if case .set(let inner) = elem {
                result.formUnion(inner)
            }
        }
        return .set(result)
    }

    public var first: TLAValue? {
        switch self {
        case .tuple(let t): return t.first
        case .set(let s): return s.first
        default: return nil
        }
    }

    public func dropFirst() -> TLAValue {
        switch self {
        case .tuple(let t): return .tuple(Array(t.dropFirst()))
        case .set(let s): return .set(Set(s.sorted().dropFirst()))
        default: return self
        }
    }

    public func union(_ other: TLAValue) -> TLAValue {
        switch (self, other) {
        case (.set(let a), .set(let b)): return .set(a.union(b))
        default: return .set([])
        }
    }

    public func intersection(_ other: TLAValue) -> TLAValue {
        switch (self, other) {
        case (.set(let a), .set(let b)): return .set(a.intersection(b))
        default: return .set([])
        }
    }

    public func subtracting(_ other: TLAValue) -> TLAValue {
        switch (self, other) {
        case (.set(let a), .set(let b)): return .set(a.subtracting(b))
        default: return .set([])
        }
    }

    public func isSubset(of other: TLAValue) -> TLAValue {
        switch (self, other) {
        case (.set(let a), .set(let b)): return .bool(a.isSubset(of: b))
        default: return .bool(false)
        }
    }

    public func contains(_ element: TLAValue) -> TLAValue {
        switch self {
        case .set(let s): return .bool(s.contains(element))
        case .tuple(let t): return .bool(t.contains(element))
        default: return .bool(false)
        }
    }

    public func updating(_ key: TLAValue, to value: TLAValue) -> TLAValue {
        switch self {
        case .function(var f):
            f[key] = value
            return .function(f)
        case .record(var r):
            if case .string(let k) = key { r[k] = value }
            return .record(r)
        default:
            return self
        }
    }

    public func filter(_ predicate: (TLAValue) -> TLAValue) -> TLAValue {
        switch self {
        case .set(let s):
            let filtered = s.filter { elem in
                if case .bool(true) = predicate(elem) { return true }
                return false
            }
            return .set(filtered)
        default:
            return .set([])
        }
    }

    public func map(_ transform: (TLAValue) -> TLAValue) -> TLAValue {
        switch self {
        case .set(let s):
            return .set(Set(s.map(transform)))
        default:
            return .set([])
        }
    }

    public func asFunctionLiteral(_ body: (TLAValue) -> TLAValue) -> TLAValue {
        switch self {
        case .set(let domain):
            var result: [TLAValue: TLAValue] = [:]
            for key in domain { result[key] = body(key) }
            return .function(result)
        default:
            return .function([:])
        }
    }

    public subscript(index: TLAValue) -> TLAValue {
        switch self {
        case .function(let f): return f[index] ?? .int(0)
        default: return .int(0)
        }
    }

    public subscript(field: String) -> TLAValue {
        switch self {
        case .record(let r): return r[field] ?? .int(0)
        default: return .int(0)
        }
    }
}

// MARK: - Tuple subscript

extension TLAValue {
    public subscript(index: Int) -> TLAValue {
        switch self {
        case .tuple(let t):
            guard index >= 0, index < t.count else { return .int(0) }
            return t[index]
        default:
            return .int(0)
        }
    }
}

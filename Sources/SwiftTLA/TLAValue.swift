public enum TLAValue: Hashable, Codable, Sendable, CustomStringConvertible {
    case int(Int)
    case bool(Bool)
    case string(String)
    case set(Set<TLAValue>)
    case tuple([TLAValue])
    case record([String: TLAValue])
    case constant(String)

    public var description: String {
        switch self {
        case .int(let n): return "\(n)"
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .string(let s): return "\"\(s)\""
        case .set(let s):
            return "{\(s.map(\.description).sorted().joined(separator: ", "))}"
        case .tuple(let t):
            return "<<\(t.map(\.description).joined(separator: ", "))>>"
        case .record(let r):
            let fields = r.sorted(by: { $0.key < $1.key }).map { "\($0.key) |-> \($0.value)" }
            return "[\(fields.joined(separator: ", "))]"
        case .constant(let name): return name
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
        case (.constant(let a), .constant(let b)): return a < b
        }
    }

    public static func sorted(_ values: Set<TLAValue>) -> [TLAValue] {
        Array(values).sorted()
    }
}

extension TLAValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

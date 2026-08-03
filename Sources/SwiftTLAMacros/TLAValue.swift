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
        case .bool(let b): return "\(b)"
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

extension TLAValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

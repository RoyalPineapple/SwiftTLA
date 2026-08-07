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

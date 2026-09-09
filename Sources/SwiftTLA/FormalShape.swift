/// Immutable structural evidence for an explicitly asserted formal value view.
public indirect enum FormalValueShape: Hashable, Sendable {
    case integer, boolean, string
    case finite(typeName: String, values: [TLAValue])
    case set(FormalValueShape)
    case sequence(FormalValueShape)
    case tuple([FormalValueShape])
    case function(key: FormalValueShape, value: FormalValueShape)
    case record([Field])
    case union(FormalValueShape, FormalValueShape)
    case unsupported(String)

    public struct Field: Hashable, Sendable {
        public let name: String
        public let shape: FormalValueShape
        public init(name: String, shape: FormalValueShape) {
            self.name = name
            self.shape = shape
        }
    }

    package var isSupported: Bool {
        switch self {
        case .unsupported: return false
        case .finite(_, let values): return !values.isEmpty && Set(values).count == values.count
        case .set(let item), .sequence(let item): return item.isSupported
        case .tuple(let items): return items.allSatisfy(\.isSupported)
        case .function(let key, let value): return key.isSupported && value.isSupported
        case .union:
            let hasSupportedAlternatives = alternatives.allSatisfy(\.isSupported)
            let structuralAlternatives = Set(alternatives.filter { !$0.isScalar })
            return hasSupportedAlternatives && structuralAlternatives.count <= 1
        case .record(let fields):
            let hasUniqueNames = Set(fields.map(\.name)).count == fields.count
            let hasSupportedFields = fields.allSatisfy { $0.shape.isSupported }
            return hasUniqueNames && hasSupportedFields
        default: return true
        }
    }

    private var alternatives: [Self] {
        if case .union(let first, let second) = self { return first.alternatives + second.alternatives }
        return [self]
    }

    private var isScalar: Bool {
        switch self {
        case .integer, .boolean, .string, .finite: true
        default: false
        }
    }

    func accepts(_ value: CompiledValue) -> Bool {
        switch (self, value) {
        case (.integer, .integer), (.boolean, .boolean), (.string, .string): return true
        case (.finite(_, let members), _): return members.contains { CompiledValue(formal: $0) == value }
        case (.set(let item), .set(let members)): return members.allSatisfy(item.accepts)
        case (.sequence(let item), .tuple(let members)): return members.allSatisfy(item.accepts)
        case (.tuple(let shapes), .tuple(let members)):
            guard members.count == shapes.count else { return false }
            return zip(shapes, members).allSatisfy { $0.accepts($1) }
        case (.function(let key, let item), .function(let values)):
            return values.allSatisfy { key.accepts($0.key) && item.accepts($0.value) }
        case (.record(let fields), .record(let record)):
            guard record.fields.count == fields.count else { return false }
            return fields.allSatisfy { field in
                record.value(for: .string(field.name)).map(field.shape.accepts) ?? false
            }
        case (.union(let first, let second), _): return first.accepts(value) || second.accepts(value)
        default: return false
        }
    }

    func predicate(for value: String, depth: Int = 0) -> String {
        var bound = "_shapeMember\(depth)"
        while value.contains(bound) || String(describing: self).contains(bound) { bound += "_" }
        func nested(_ shape: Self, _ value: String) -> String { shape.predicate(for: value, depth: depth + 1) }
        switch self {
        case .integer: return "\(value) \\in Int"
        case .boolean: return "\(value) \\in BOOLEAN"
        case .string: return "\(value) \\in STRING"
        case .finite(_, let values): return "\(value) \\in {\(values.map(\.description).joined(separator: ", "))}"
        case .set(let item): return "(\\A \(bound) \\in \(value) : \(nested(item, bound)))"
        case .sequence(let item):
            return "(DOMAIN \(value) = 1..Len(\(value)) /\\ (\\A \(bound) \\in DOMAIN \(value) : \(nested(item, "\(value)[\(bound)]"))))"
        case .tuple(let items):
            let checks = items.enumerated().map { nested($0.element, "\(value)[\($0.offset + 1)]") }
            return "(DOMAIN \(value) = 1..\(items.count)" + checks.map { " /\\ (\($0))" }.joined() + ")"
        case .function(let key, let item):
            return "(\\A \(bound) \\in DOMAIN \(value) : (\(nested(key, bound))) /\\ (\(nested(item, "\(value)[\(bound)]"))))"
        case .record(let fields):
            let keys = fields.map { TLAValue.string($0.name).description }.joined(separator: ", ")
            let checks = fields.map { nested($0.shape, "\(value)[\(TLAValue.string($0.name).description)]") }
            return "(DOMAIN \(value) = {\(keys)}" + checks.map { " /\\ (\($0))" }.joined() + ")"
        case .union:
            let ordered = alternatives.filter(\.isScalar) + alternatives.filter { !$0.isScalar }
            return "(" + ordered.map { "(\(nested($0, value)))" }.joined(separator: " \\/ ") + ")"
        case .unsupported: return "FALSE"
        }
    }
}

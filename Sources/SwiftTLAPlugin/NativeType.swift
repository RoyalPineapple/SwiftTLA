import SwiftTLA

struct NativeField: Hashable, Sendable {
    let name: String
    let type: NativeType

}

/// Type evidence for code generation, never a runtime value representation.
indirect enum NativeType: Hashable, Sendable {
    case unknown
    case int, bool, string, atom, control
    case named(String)
    case finite([CompiledValue])
    case union([NativeType])
    case collectionMember(VariableID, swiftType: String)
    case set(NativeType)
    case array(NativeType)
    case dictionary(NativeType, NativeType)
    case record([NativeField])
    case tuple([NativeType])

    var components: [NativeType] {
        switch self {
        case .set(let value), .array(let value): [value]
        case .dictionary(let key, let value): [key, value]
        case .record(let fields): fields.map(\.type)
        case .tuple(let values), .union(let values): values
        default: []
        }
    }

    private func embeds(_ other: NativeType) -> Bool {
        if self == other { return true }
        guard other != .unknown else { return false }
        if components.contains(where: { $0.embeds(other) }) { return true }
        switch (self, other) {
        case (.array(let a), .array(let b)), (.set(let a), .set(let b)): return a.embeds(b)
        case (.dictionary(let a, let b), .dictionary(let c, let d)): return a.embeds(c) && b.embeds(d)
        case (.tuple(let a), .tuple(let b)), (.union(let a), .union(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.embeds($1) }
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return zip(a, b).allSatisfy { $0.type.embeds($1.type) }
        default: return false
        }
    }

    func strictlyContains(_ other: NativeType) -> Bool { self != other && embeds(other) }

    var swiftType: String {
        switch self {
        case .unknown: "<unresolved>"
        case .int: "Int"
        case .bool: "Bool"
        case .string: "String"
        case .atom: "_Atom"
        case .control: "_ControlLocation"
        case .named(let name): name
        case .finite: "FiniteValue"
        case .union: "UnionValue"
        case .collectionMember(_, let name): name
        case .set(let element): "Set<\(element.swiftType)>"
        case .array(let element): "[\(element.swiftType)]"
        case .dictionary(let key, let value): "[\(key.swiftType): \(value.swiftType)]"
        case .record(let fields): "(" + fields.map { "\($0.name): \($0.type.swiftType)" }.joined(separator: ", ") + ")"
        case .tuple(let elements): "(" + elements.map(\.swiftType).joined(separator: ", ") + ")"
        }
    }

    var resolved: Bool {
        switch self {
        case .unknown: false
        case .set(let element), .array(let element): element.resolved
        case .dictionary(let key, let value): key.resolved && value.resolved
        case .record(let fields): fields.allSatisfy { $0.type.resolved }
        case .tuple(let elements), .union(let elements): elements.allSatisfy(\.resolved)
        default: true
        }
    }

    func missingTypePaths(from path: String = "value") -> [String] {
        switch self {
        case .unknown: return [path]
        case .set(let element), .array(let element):
            return element.missingTypePaths(from: path + ".element")
        case .dictionary(let key, let value):
            return key.missingTypePaths(from: path + ".key")
                + value.missingTypePaths(from: path + ".value")
        case .record(let fields):
            return fields.flatMap { $0.type.missingTypePaths(from: path + "." + $0.name) }
        case .tuple(let elements), .union(let elements):
            return elements.enumerated().flatMap {
                $0.element.missingTypePaths(from: path + "[\($0.offset + 1)]")
            }
        default: return []
        }
    }
}

package struct CompiledFieldType: Hashable, Sendable {
    package let name: String
    package let type: CompiledValueType
    package init(name: String, type: CompiledValueType) {
        self.name = name
        self.type = type
    }

}

/// Compiler value types carried through checking and backend generation.
package indirect enum CompiledValueType: Hashable, Sendable {
    case unknown
    case int, bool, string, modelValue, controlLocation
    case named(String)
    case finite([CompiledValue])
    case union([CompiledValueType])
    case collectionMember(VariableID, swiftType: String)
    case set(CompiledValueType)
    case array(CompiledValueType)
    case dictionary(CompiledValueType, CompiledValueType)
    case record([CompiledFieldType])
    case tuple([CompiledValueType])

    package var components: [CompiledValueType] {
        switch self {
        case .set(let value), .array(let value): [value]
        case .dictionary(let key, let value): [key, value]
        case .record(let fields): fields.map(\.type)
        case .tuple(let values), .union(let values): values
        default: []
        }
    }

    private func embeds(_ other: CompiledValueType) -> Bool {
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

    package func strictlyContains(_ other: CompiledValueType) -> Bool { self != other && embeds(other) }

    package var swiftType: String {
        switch self {
        case .unknown: "<unresolved>"
        case .int: "Int"
        case .bool: "Bool"
        case .string: "String"
        case .modelValue: "_ModelValue"
        case .controlLocation: "_ControlLocation"
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

    package var resolved: Bool {
        switch self {
        case .unknown: false
        case .set(let element), .array(let element): element.resolved
        case .dictionary(let key, let value): key.resolved && value.resolved
        case .record(let fields): fields.allSatisfy { $0.type.resolved }
        case .tuple(let elements), .union(let elements): elements.allSatisfy(\.resolved)
        default: true
        }
    }

    package func missingTypePaths(from path: String = "value") -> [String] {
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

extension CompiledValueType {
    package static func diagnostic(_ path: String, _ actual: String) -> CompilationDiagnostic {
        .init(code: .unsupportedGeneratedValueShape, stage: .lowering,
              path: "nativeMachine.\(path)", expected: "a statically resolved native Swift value shape",
              actual: actual, nextSafeAction: "Use a concrete typed value and an operation supported by native machine generation.")
    }

    package static func unresolvedDiagnostic(_ type: CompiledValueType, at path: String) -> CompilationDiagnostic {
        .init(code: .unresolvedGeneratedValueShape, stage: .lowering,
              path: "nativeMachine.\(path)", expected: "concrete Swift types for every value",
              actual: "type inference could not determine \(type.missingTypePaths().joined(separator: ", "))",
              nextSafeAction: "Inspect compiler type propagation for this expression; this diagnostic does not establish that the model is unsupported.")
    }


    package static func merge(_ lhs: CompiledValueType, _ rhs: CompiledValueType) throws -> CompiledValueType {
        if lhs == rhs || rhs == .unknown { return lhs }
        if lhs == .unknown { return rhs }
        switch (lhs, rhs) {
        case (.set(let a), .set(let b)): return .set(try merge(a, b))
        case (.array(let a), .array(let b)): return .array(try merge(a, b))
        case (.dictionary(let ak, let av), .dictionary(let bk, let bv)):
            return .dictionary(try merge(ak, bk), try merge(av, bv))
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return .tuple(try zip(a, b).map { try merge($0, $1) })
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return .record(try zip(a, b).map { .init(name: $0.name, type: try merge($0.type, $1.type)) })
        default: throw CompiledValueType.diagnostic("type", "incompatible shapes \(lhs.swiftType) and \(rhs.swiftType)")
        }
    }


    package static func normalizedUnion(_ branches: [CompiledValueType], namedDomains: [String: Set<CompiledValue>]) throws -> CompiledValueType {
        var scalarValues = Set<CompiledValue>()
        var composite: [CompiledValueType] = []
        func append(_ branch: CompiledValueType) throws {
            switch branch {
            case .union(let nested): for item in nested { try append(item) }
            case .finite(let values): scalarValues.formUnion(values)
            case .named(let name):
                guard let values = namedDomains[name] else { throw CompiledValueType.diagnostic("union", "union branch has no finite declared domain") }
                scalarValues.formUnion(values)
            default:
                if !composite.contains(branch) { composite.append(branch) }
            }
        }
        for branch in branches { try append(branch) }
        func kind(_ type: CompiledValueType) -> Int? {
            switch type {
            case .int: 0
            case .bool: 1
            case .string: 2
            case .modelValue: 8
            case .set: 4
            case .array, .tuple: 5
            case .record: 6
            case .dictionary: 7
            default: nil
            }
        }
        for (index, branch) in composite.enumerated() {
            guard let rank = kind(branch), branch.resolved else { throw CompiledValueType.diagnostic("union", "union alternatives require finite scalars or resolved collection shapes") }
            if composite.prefix(index).contains(where: { kind($0) == rank }) {
                throw CompiledValueType.diagnostic("union", "overlapping composite union alternatives are ambiguous")
            }
            if scalarValues.contains(where: { value in
                switch (value, branch) {
                case (.set, .set), (.tuple, .array), (.tuple, .tuple), (.record, .record), (.function, .dictionary): true
                default: false
                }
            }) { throw CompiledValueType.diagnostic("union", "finite and composite union alternatives overlap") }
        }
        scalarValues = scalarValues.filter { member in
            !composite.contains { type in
                let primitive = member.orderingKind < 4 || member.orderingKind == 8
                return primitive && kind(type) == member.orderingKind
            }
        }
        if composite.isEmpty { return .finite(scalarValues.sorted()) }
        var alternatives = composite.sorted { kind($0)! < kind($1)! }
        if !scalarValues.isEmpty { alternatives.insert(.finite(scalarValues.sorted()), at: 0) }
        return alternatives.count == 1 ? alternatives[0] : .union(alternatives)
    }

}

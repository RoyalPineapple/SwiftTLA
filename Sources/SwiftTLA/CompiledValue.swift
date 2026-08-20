indirect enum CompiledValue: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case controlLabel(ControlLabelID)
    case set(Set<CompiledValue>)
    case tuple([CompiledValue])
    case record([String: CompiledValue])
    case function([CompiledValue: CompiledValue])
    case constant(String)

    init(formal value: TLAValue) {
        switch value {
        case .int(let value):
            self = .integer(value)
        case .bool(let value):
            self = .boolean(value)
        case .string(let value):
            self = .string(value)
        case .set(let values):
            self = .set(Set(values.map { Self(formal: $0) }))
        case .tuple(let values):
            self = .tuple(values.map { Self(formal: $0) })
        case .record(let values):
            self = .record(values.mapValues { Self(formal: $0) })
        case .function(let values):
            self = .function(Dictionary(uniqueKeysWithValues: values.map {
                (Self(formal: $0.key), Self(formal: $0.value))
            }))
        case .constant(let value):
            self = .constant(value)
        }
    }

    func rendered(using layout: CompiledLayout) throws -> TLAValue {
        switch self {
        case .integer(let value):
            return .int(value)
        case .boolean(let value):
            return .bool(value)
        case .string(let value):
            return .string(value)
        case .controlLabel(let id):
            guard let label = layout.controlLabel(id) else {
                throw CompiledEvaluationError.invalidControlLabelID(id)
            }
            return .string(label.renderedName)
        case .set(let values):
            return .set(try Set(values.map { try $0.rendered(using: layout) }))
        case .tuple(let values):
            return .tuple(try values.map { try $0.rendered(using: layout) })
        case .record(let values):
            return .record(try values.reduce(into: [String: TLAValue]()) { result, field in
                result[field.key] = try field.value.rendered(using: layout)
            })
        case .function(let values):
            return .function(try values.reduce(into: [TLAValue: TLAValue]()) { result, entry in
                result[try entry.key.rendered(using: layout)] = try entry.value.rendered(using: layout)
            })
        case .constant(let value):
            return .constant(value)
        }
    }

    func transformingFormalValues(_ transform: (TLAValue) -> TLAValue) -> CompiledValue {
        switch self {
        case .integer, .boolean, .string, .controlLabel, .constant:
            return self
        case .set(let values):
            return .set(Set(values.map { $0.transformingFormalValues(transform) }))
        case .tuple(let values):
            return .tuple(values.map { $0.transformingFormalValues(transform) })
        case .record(let values):
            return .record(values.mapValues { $0.transformingFormalValues(transform) })
        case .function(let values):
            return .function(Dictionary(uniqueKeysWithValues: values.map {
                ($0.key.transformingFormalValues(transform), $0.value.transformingFormalValues(transform))
            }))
        }
    }

    func contains(_ value: TLAValue) -> Bool {
        switch self {
        case .integer(let current):
            return valueContains(.int(current), value)
        case .boolean(let current):
            return valueContains(.bool(current), value)
        case .string(let current):
            return valueContains(.string(current), value)
        case .controlLabel:
            return false
        case .set(let values):
            return values.contains { $0.contains(value) }
        case .tuple(let values):
            return values.contains { $0.contains(value) }
        case .record(let values):
            return values.values.contains { $0.contains(value) }
        case .function(let values):
            return values.contains { $0.key.contains(value) || $0.value.contains(value) }
        case .constant(let current):
            return valueContains(.constant(current), value)
        }
    }

    static func sorted(_ values: Set<CompiledValue>) -> [CompiledValue] {
        values.sorted { $0.canonicalEncoding < $1.canonicalEncoding }
    }

    private var canonicalEncoding: String {
        switch self {
        case .integer(let value):
            return "integer:\(value)"
        case .boolean(let value):
            return "boolean:\(value)"
        case .string(let value):
            return "string:\(value)"
        case .controlLabel(let value):
            return "control:\(value.ordinal)"
        case .set(let values):
            return "set:[\(Self.sorted(values).map(\.canonicalEncoding).joined(separator: ","))]"
        case .tuple(let values):
            return "tuple:[\(values.map(\.canonicalEncoding).joined(separator: ","))]"
        case .record(let values):
            return "record:[\(values.keys.sorted().map { "\($0):\(values[$0]?.canonicalEncoding ?? "")" }.joined(separator: ","))]"
        case .function(let values):
            return "function:[\(values.keys.sorted { $0.canonicalEncoding < $1.canonicalEncoding }.map { "\($0.canonicalEncoding):\(values[$0]?.canonicalEncoding ?? "")" }.joined(separator: ","))]"
        case .constant(let value):
            return "constant:\(value)"
        }
    }
}

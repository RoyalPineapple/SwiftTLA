struct CompiledRecord: Hashable, Sendable {
    struct Field: Hashable, Sendable {
        let name: String
        let value: CompiledValue
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.name < $1.name }
    }

    func value(named name: String) -> CompiledValue? {
        fields.first { $0.name == name }?.value
    }

    func replacing(_ value: CompiledValue, for name: String) -> CompiledRecord {
        var replaced = false
        let updated = fields.map { field -> Field in
            guard field.name == name else { return field }
            replaced = true
            return .init(name: name, value: value)
        }
        return CompiledRecord(replaced ? updated : updated + [.init(name: name, value: value)])
    }
}

indirect enum CompiledValue: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case controlLabel(ControlLabelID)
    case set(Set<CompiledValue>)
    case tuple([CompiledValue])
    case record(CompiledRecord)
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
            self = .record(CompiledRecord(values.fields.map {
                .init(name: $0.name, value: Self(formal: $0.value))
            }))
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
            return .record(TLARecord(try values.fields.map {
                .init($0.name, try $0.value.rendered(using: layout))
            }))
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
            return .record(CompiledRecord(values.fields.map {
                .init(name: $0.name, value: $0.value.transformingFormalValues(transform))
            }))
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
            return values.fields.contains { $0.value.contains(value) }
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
            return "record:[\(values.fields.map { "\($0.name):\($0.value.canonicalEncoding)" }.joined(separator: ","))]"
        case .function(let values):
            return "function:[\(values.keys.sorted { $0.canonicalEncoding < $1.canonicalEncoding }.map { "\($0.canonicalEncoding):\(values[$0]?.canonicalEncoding ?? "")" }.joined(separator: ","))]"
        case .constant(let value):
            return "constant:\(value)"
        }
    }
}

struct CompiledRecord: Hashable, Sendable {
    struct Field: Hashable, Sendable {
        let key: CompiledValue
        let value: CompiledValue
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.key.canonicalEncoding < $1.key.canonicalEncoding }
    }

    func value(for key: CompiledValue) -> CompiledValue? {
        fields.first { $0.key == key }?.value
    }

    func replacing(_ value: CompiledValue, for key: CompiledValue) -> CompiledRecord {
        var replaced = false
        let updated = fields.map { current -> Field in
            guard current.key == key else { return current }
            replaced = true
            return .init(key: key, value: value)
        }
        return CompiledRecord(replaced ? updated : updated + [.init(key: key, value: value)])
    }
}

indirect enum CompiledValue: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case controlLocation(ControlLocationID)
    case set(Set<CompiledValue>)
    case tuple([CompiledValue])
    case record(CompiledRecord)
    case function([CompiledValue: CompiledValue])
    case constant(String)

    init(formal value: TLAValue, using layout: CompiledLayout) throws {
        switch value {
        case .int(let value):
            self = .integer(value)
        case .bool(let value):
            self = .boolean(value)
        case .string(let value):
            self = .string(value)
        case .set(let values):
            self = .set(try Set(values.map { try Self(formal: $0, using: layout) }))
        case .tuple(let values):
            self = .tuple(try values.map { try Self(formal: $0, using: layout) })
        case .record(let values):
            self = .record(CompiledRecord(try values.fields.map { entry in
                .init(key: .string(entry.name), value: try Self(formal: entry.value, using: layout))
            }))
        case .function(let values):
            self = .function(try Dictionary(uniqueKeysWithValues: values.map {
                (try Self(formal: $0.key, using: layout), try Self(formal: $0.value, using: layout))
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
        case .controlLocation(let id):
            guard let label = layout.controlLocation(id) else {
                throw CompiledEvaluationError.invalidControlLocationID(id)
            }
            return .string(label.sourceName)
        case .set(let values):
            return .set(try Set(values.map { try $0.rendered(using: layout) }))
        case .tuple(let values):
            return .tuple(try values.map { try $0.rendered(using: layout) })
        case .record(let values):
            return .record(TLARecord(try values.fields.map { field in
                guard case .string(let name) = try field.key.rendered(using: layout) else {
                    throw CompiledEvaluationError.invalidRecordKey(field.key)
                }
                return .init(name, try field.value.rendered(using: layout))
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
        case .integer, .boolean, .string, .controlLocation, .constant:
            return self
        case .set(let values):
            return .set(Set(values.map { $0.transformingFormalValues(transform) }))
        case .tuple(let values):
            return .tuple(values.map { $0.transformingFormalValues(transform) })
        case .record(let values):
            return .record(CompiledRecord(values.fields.map {
                .init(key: $0.key.transformingFormalValues(transform), value: $0.value.transformingFormalValues(transform))
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
        case .controlLocation:
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

    var canonicalEncoding: String {
        switch self {
        case .integer(let value):
            return "integer:\(value)"
        case .boolean(let value):
            return "boolean:\(value)"
        case .string(let value):
            return "string:\(value)"
        case .controlLocation(let value):
            return "control:\(value.ordinal)"
        case .set(let values):
            return "set:[\(Self.sorted(values).map(\.canonicalEncoding).joined(separator: ","))]"
        case .tuple(let values):
            return "tuple:[\(values.map(\.canonicalEncoding).joined(separator: ","))]"
        case .record(let values):
            return "record:[\(values.fields.map { "\($0.key.canonicalEncoding):\($0.value.canonicalEncoding)" }.joined(separator: ","))]"
        case .function(let values):
            return "function:[\(values.keys.sorted { $0.canonicalEncoding < $1.canonicalEncoding }.map { "\($0.canonicalEncoding):\(values[$0]?.canonicalEncoding ?? "")" }.joined(separator: ","))]"
        case .constant(let value):
            return "constant:\(value)"
        }
    }
}

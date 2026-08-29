struct CompiledRecord: Hashable, Sendable {
    struct Field: Hashable, Sendable, Comparable {
        let key: CompiledValue
        let value: CompiledValue

        static func < (lhs: Field, rhs: Field) -> Bool {
            lhs.key == rhs.key ? lhs.value < rhs.value : lhs.key < rhs.key
        }
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields.sorted()
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

indirect enum CompiledValue: Hashable, Sendable, Comparable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case controlLocation(ControlLocationID)
    case set(Set<CompiledValue>)
    case tuple([CompiledValue])
    case record(CompiledRecord)
    case function([CompiledValue: CompiledValue])
    case constant(String)

    init(formal value: TLAValue) {
        self = Self.formalValue(value)
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

    func applying(_ mapping: [CompiledValue: CompiledValue]) -> CompiledValue {
        if let replacement = mapping[self] { return replacement }
        switch self {
        case .integer, .boolean, .string, .constant, .controlLocation:
            return self
        case .set(let values):
            return .set(Set(values.map { $0.applying(mapping) }))
        case .tuple(let values):
            return .tuple(values.map { $0.applying(mapping) })
        case .record(let values):
            return .record(CompiledRecord(values.fields.map {
                .init(key: $0.key.applying(mapping), value: $0.value.applying(mapping))
            }))
        case .function(let values):
            return .function(Dictionary(uniqueKeysWithValues: values.map {
                ($0.key.applying(mapping), $0.value.applying(mapping))
            }))
        }
    }

    private static func formalValue(_ value: TLAValue) -> CompiledValue {
        switch value {
        case .int(let value): return .integer(value)
        case .bool(let value): return .boolean(value)
        case .string(let value): return .string(value)
        case .constant(let value): return .constant(value)
        case .set(let values): return .set(Set(values.map(formalValue)))
        case .tuple(let values): return .tuple(values.map(formalValue))
        case .record(let fields):
            return .record(CompiledRecord(fields.fields.map {
                .init(key: .string($0.name), value: formalValue($0.value))
            }))
        case .function(let values):
            return .function(Dictionary(uniqueKeysWithValues: values.map {
                (formalValue($0.key), formalValue($0.value))
            }))
        }
    }

    func contains(_ value: CompiledValue) -> Bool {
        if self == value { return true }
        switch self {
        case .integer, .boolean, .string, .controlLocation, .constant:
            return false
        case .set(let values):
            return values.contains { $0.contains(value) }
        case .tuple(let values):
            return values.contains { $0.contains(value) }
        case .record(let values):
            return values.fields.contains { $0.value.contains(value) }
        case .function(let values):
            return values.contains { $0.key.contains(value) || $0.value.contains(value) }
        }
    }

    static func sorted(_ values: Set<CompiledValue>) -> [CompiledValue] {
        values.sorted()
    }

    static func < (lhs: CompiledValue, rhs: CompiledValue) -> Bool {
        let lhsKind = lhs.orderingKind
        let rhsKind = rhs.orderingKind
        guard lhsKind == rhsKind else { return lhsKind < rhsKind }

        switch (lhs, rhs) {
        case (.integer(let lhs), .integer(let rhs)):
            return lhs < rhs
        case (.boolean(let lhs), .boolean(let rhs)):
            return lhs == false && rhs == true
        case (.string(let lhs), .string(let rhs)):
            return lhs < rhs
        case (.controlLocation(let lhs), .controlLocation(let rhs)):
            return lhs.ordinal < rhs.ordinal
        case (.set(let lhs), .set(let rhs)):
            return Self.sorted(lhs).lexicographicallyPrecedes(Self.sorted(rhs))
        case (.tuple(let lhs), .tuple(let rhs)):
            return lhs.lexicographicallyPrecedes(rhs)
        case (.record(let lhs), .record(let rhs)):
            return lhs.fields.lexicographicallyPrecedes(rhs.fields)
        case (.function(let lhs), .function(let rhs)):
            let lhsFields = lhs.map { CompiledRecord.Field(key: $0.key, value: $0.value) }.sorted()
            let rhsFields = rhs.map { CompiledRecord.Field(key: $0.key, value: $0.value) }.sorted()
            return lhsFields.lexicographicallyPrecedes(rhsFields)
        case (.constant(let lhs), .constant(let rhs)):
            return lhs < rhs
        default:
            return false
        }
    }

    private var orderingKind: Int {
        switch self {
        case .integer: 0
        case .boolean: 1
        case .string: 2
        case .controlLocation: 3
        case .set: 4
        case .tuple: 5
        case .record: 6
        case .function: 7
        case .constant: 8
        }
    }
}

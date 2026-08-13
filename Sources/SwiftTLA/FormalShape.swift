public protocol FormalValue: TLAValueConvertible, Sendable, Equatable, Hashable {
    static var formalTypeIdentity: FormalTypeIdentity { get }
}

extension Int: FormalValue {
    public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "swift.Int")
}

extension Bool: FormalValue {
    public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "swift.Bool")
}

extension String: FormalValue {
    public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "swift.String")
}

extension TLAValue: FormalValue {
    public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "swift-tla.TLAValue")
}

public protocol FiniteDomainKey: FormalValue, TLAValueType {
    static var formalDomain: [Self] { get }
}

extension FiniteDomainKey {
    /// The first declared member is only the Swift construction default.
    /// Formal initial state is always supplied explicitly by `Shared` or `Local`.
    public static var defaultValue: Self {
        precondition(!formalDomain.isEmpty, "A finite domain needs at least one member.")
        return formalDomain[0]
    }
}

public enum FormalShapeValidationError: Error, Sendable, Equatable {
    case emptyFiniteDomain
    case duplicateFiniteDomainMember
    case incompleteFiniteMap
    case invalidShapeIdentifier
    case duplicateRecordField
}

public struct FormalTypeIdentity: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func of<Value: FormalValue>(_ type: Value.Type) -> FormalTypeIdentity {
        Value.formalTypeIdentity
    }
}

public struct ErasedDomainShape: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity
    public let members: [TLAValue]

    public init(id: String, name: String, typeIdentity: FormalTypeIdentity, members: [TLAValue]) throws {
        guard !id.isEmpty, !name.isEmpty else {
            throw FormalShapeValidationError.invalidShapeIdentifier
        }
        guard !members.isEmpty else {
            throw FormalShapeValidationError.emptyFiniteDomain
        }
        guard Set(members).count == members.count else {
            throw FormalShapeValidationError.duplicateFiniteDomainMember
        }
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
        self.members = members
    }
}

public struct DomainShape<Value: FormalValue>: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity
    public let members: [Value]
    public let provenance: String?

    public init(
        id: String,
        name: String,
        members: [Value],
        typeIdentity: FormalTypeIdentity = .of(Value.self),
        provenance: String? = nil
    ) throws {
        guard !id.isEmpty, !name.isEmpty else {
            throw FormalShapeValidationError.invalidShapeIdentifier
        }
        guard !members.isEmpty else {
            throw FormalShapeValidationError.emptyFiniteDomain
        }
        guard Set(members).count == members.count else {
            throw FormalShapeValidationError.duplicateFiniteDomainMember
        }
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
        self.members = members
        self.provenance = provenance
    }

    public var erased: ErasedDomainShape {
        try! ErasedDomainShape(id: id, name: name, typeIdentity: typeIdentity, members: members.map(\.tlaValue))
    }

    public static func == (lhs: DomainShape<Value>, rhs: DomainShape<Value>) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.typeIdentity == rhs.typeIdentity && lhs.members == rhs.members
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(typeIdentity)
        hasher.combine(members)
    }
}

public struct ErasedFieldShape: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity

    public init(id: String, name: String, typeIdentity: FormalTypeIdentity) throws {
        guard !id.isEmpty, !name.isEmpty else {
            throw FormalShapeValidationError.invalidShapeIdentifier
        }
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
    }
}

public struct FieldShape<Record: FormalValue, Value: FormalValue>: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity
    public let provenance: String?

    public init(
        id: String,
        name: String,
        typeIdentity: FormalTypeIdentity = .of(Value.self),
        provenance: String? = nil
    ) throws {
        guard !id.isEmpty, !name.isEmpty else {
            throw FormalShapeValidationError.invalidShapeIdentifier
        }
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
        self.provenance = provenance
    }

    public var erased: ErasedFieldShape {
        try! ErasedFieldShape(id: id, name: name, typeIdentity: typeIdentity)
    }

    public static func == (lhs: FieldShape<Record, Value>, rhs: FieldShape<Record, Value>) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.typeIdentity == rhs.typeIdentity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(typeIdentity)
    }
}

public struct ErasedRecordShape: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity
    public let fields: [ErasedFieldShape]

    public init(id: String, name: String, typeIdentity: FormalTypeIdentity, fields: [ErasedFieldShape]) throws {
        guard !id.isEmpty, !name.isEmpty else {
            throw FormalShapeValidationError.invalidShapeIdentifier
        }
        guard Set(fields.map(\.id)).count == fields.count, Set(fields.map(\.name)).count == fields.count else {
            throw FormalShapeValidationError.duplicateRecordField
        }
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
        self.fields = fields
    }
}

public struct RecordShape<Record: FormalValue>: Hashable, Sendable {
    public let id: String
    public let name: String
    public let typeIdentity: FormalTypeIdentity
    public let fields: [ErasedFieldShape]
    public let provenance: String?

    public init(
        id: String,
        name: String,
        fields: [ErasedFieldShape],
        typeIdentity: FormalTypeIdentity = .of(Record.self),
        provenance: String? = nil
    ) throws {
        _ = try ErasedRecordShape(id: id, name: name, typeIdentity: typeIdentity, fields: fields)
        self.id = id
        self.name = name
        self.typeIdentity = typeIdentity
        self.fields = fields
        self.provenance = provenance
    }

    public var erased: ErasedRecordShape {
        try! ErasedRecordShape(id: id, name: name, typeIdentity: typeIdentity, fields: fields)
    }

    public static func == (lhs: RecordShape<Record>, rhs: RecordShape<Record>) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.typeIdentity == rhs.typeIdentity && lhs.fields == rhs.fields
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(typeIdentity)
        hasher.combine(fields)
    }
}

public struct FormalShapeGraph: Hashable, Sendable {
    public let domains: [ErasedDomainShape]
    public let records: [ErasedRecordShape]

    public init(domains: [ErasedDomainShape] = [], records: [ErasedRecordShape] = []) {
        self.domains = domains
        self.records = records
    }
}

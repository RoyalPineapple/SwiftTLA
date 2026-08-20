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

public protocol FiniteDomainKey: FormalValue, TLAValueType, FiniteTLAValueDomain {
    static var formalDomain: [Self] { get }
}

extension FiniteDomainKey {
    /// A finite function and a PlusCal process use the same declared members.
    public static var finiteValues: [Self] { formalDomain }
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

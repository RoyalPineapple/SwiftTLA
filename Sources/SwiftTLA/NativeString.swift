import Foundation

/// Native string storage that preserves an explicit formal encoding.
@_documentation(visibility: internal)
public struct _NativeString: Hashable, Sendable, Comparable, TLAValueType,
    ExpressibleByStringLiteral, ExpressibleByStringInterpolation, CustomStringConvertible {
    private let value: String

    public init(sourceString value: String) {
        self.value = value.precomposedStringWithCanonicalMapping
    }
    public init(formalString value: String) { self.value = value }
    public init(stringLiteral value: String) { self.init(sourceString: value) }
    public init(stringInterpolation value: String.StringInterpolation) {
        self.init(sourceString: String(stringInterpolation: value))
    }
    public init?(formalValue: TLAValue) {
        guard case .string(let value) = formalValue else { return nil }
        self.init(formalString: value)
    }
    public static var defaultValue: Self { Self(formalString: "") }
    public static var formalValueShape: FormalValueShape { .string }
    public var tlaValue: TLAValue { .string(value) }
    public var formalString: String { value }
    public var description: String { value }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        FormalStringIdentity.equal(lhs.value, rhs.value)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        FormalStringIdentity.less(lhs.value, rhs.value)
    }
    public func hash(into hasher: inout Hasher) {
        FormalStringIdentity.hash(value, into: &hasher)
    }
}

import CoreFoundation
import Foundation

/// The structural values retained by a formal tool's JSON state output.
/// Collection and model-value types are resolved by the generated state schema.
public indirect enum TLAJSONValue: Equatable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case array([Self])
    case object([String: Self])

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let a), .integer(let b)): return a == b
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.string(let a), .string(let b)): return FormalStringIdentity.equal(a, b)
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            let left = a.sorted { FormalStringIdentity.less($0.key, $1.key) }
            let right = b.sorted { FormalStringIdentity.less($0.key, $1.key) }
            return zip(left, right).allSatisfy {
                FormalStringIdentity.equal($0.0.key, $0.1.key) && $0.0.value == $0.1.value
            }
        default: return false
        }
    }

    package static func decode(_ raw: Any, at path: String) throws -> Self {
        if let object = raw as? [String: Any] {
            return .object(try object.mapValues { try decode($0, at: path) })
        }
        if let array = raw as? [Any] {
            return .array(try array.enumerated().map { try decode($0.element, at: "\(path)[\($0.offset)]") })
        }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            guard !CFNumberIsFloatType(number), let value = Int(number.stringValue) else {
                throw TLAStateProjectionDiagnostic.invalidValue(path: path)
            }
            return .integer(value)
        }
        if let string = raw as? String { return .string(string) }
        throw TLAStateProjectionDiagnostic.invalidValue(path: path)
    }
}

/// Validated formal JSON input at the native-machine reconstruction boundary.
public struct TLAJSONStateProjection: Sendable {
    private let values: [TLAStateProjection.Token: TLAJSONValue]

    package init(validatingJSON bindings: [String: Any]) throws {
        var values: [TLAStateProjection.Token: TLAJSONValue] = [:]
        for (name, value) in bindings {
            guard let token = TLAStateProjection.Token(validating: name) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: name)
            }
            guard values.updateValue(try TLAJSONValue.decode(value, at: name), forKey: token) == nil else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: name)
            }
        }
        self.values = values
    }

    public func value(for token: TLAStateProjection.Token) -> TLAJSONValue? { values[token] }
    public var count: Int { values.count }
}

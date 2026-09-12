
public enum TLAStateProjectionDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidKey(path: String)
    case invalidConstant(path: String)
    case invalidValue(path: String)

    public var description: String {
        switch self {
        case .invalidKey(let path):
            return "Invalid TLA state key at \(path)"
        case .invalidConstant(let path):
            return "Invalid TLA constant at \(path)"
        case .invalidValue(let path):
            return "Invalid TLA state value at \(path)"
        }
    }
}

/// Validated state at the explicit native-to-TLA serialization boundary.
public struct TLAStateProjection: Sendable, Hashable, CustomStringConvertible {
    /// A validated identifier for a value in a formal state projection.
    public struct Token: Sendable, Hashable, CustomStringConvertible {
        fileprivate let identifier: String

        public init?(validating identifier: String) {
            guard let first = identifier.unicodeScalars.first,
                  first.properties.isAlphabetic || first == "_",
                  identifier.unicodeScalars.dropFirst().allSatisfy({
                      $0.properties.isAlphabetic || $0.properties.isIDContinue
                  }) else {
                return nil
            }
            self.identifier = identifier
        }

        public var description: String { identifier }
    }

    /// One validated value in a state projection.
    public struct Entry: Sendable, Hashable {
        public let token: Token
        public let value: TLAValue

        public init(token: Token, value: TLAValue) {
            self.token = token
            self.value = value
        }
    }

    private let storedEntries: [Entry]

    public init(validating entries: [Entry]) throws {
        var tokens = Set<Token>()
        for entry in entries {
            guard tokens.insert(entry.token).inserted else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: entry.token.identifier)
            }
            try Self.validate(entry.value, at: entry.token.identifier)
        }
        storedEntries = entries.sorted { $0.token.identifier < $1.token.identifier }
    }

    public func value(for token: Token) -> TLAValue? {
        storedEntries.first { $0.token == token }?.value
    }

    public var entries: [Entry] {
        storedEntries
    }

    public var description: String {
        entries.map { "\($0.token) = \($0.value)" }.joined(separator: ", ")
    }

    private static func validate(_ value: TLAValue, at path: String) throws {
        switch value {
        case .int, .bool, .string:
            return
        case .constant(let name):
            guard Token(validating: name) != nil else {
                throw TLAStateProjectionDiagnostic.invalidConstant(path: path)
            }
        case .set(let values):
            for (index, value) in values.sorted().enumerated() {
                try validate(value, at: "\(path){\(index)}")
            }
        case .tuple(let values):
            for (index, value) in values.enumerated() {
                try validate(value, at: "\(path)[\(index)]")
            }
        case .record(let fields):
            var names: Set<String> = []
            for field in fields.fields {
                guard Token(validating: field.name) != nil, names.insert(field.name).inserted else {
                    throw TLAStateProjectionDiagnostic.invalidKey(path: "\(path).\(field.name)")
                }
                try validate(field.value, at: "\(path).\(field.name)")
            }
        case .function(let mapping):
            for (key, value) in mapping {
                try validate(key, at: "\(path).key")
                try validate(value, at: "\(path).value")
            }
        }
    }
}

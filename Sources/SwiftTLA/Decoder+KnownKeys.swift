private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    package func container<Key>(
        validatingKeys keyType: Key.Type
    ) throws -> KeyedDecodingContainer<Key> where Key: CodingKey & CaseIterable {
        let actual = try container(keyedBy: AnyCodingKey.self)
        let known = Set(Key.allCases.map(\.stringValue))
        let unknown = Set(actual.allKeys.map(\.stringValue)).subtracting(known)
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath,
                debugDescription: "Unknown fields: \(unknown.sorted().joined(separator: ", "))"))
        }
        return try container(keyedBy: keyType)
    }
}

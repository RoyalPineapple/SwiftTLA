import Foundation
import SwiftTLA

/// Versioned, complete value identity for parity evidence. This is a wire
/// contract between independent producers, not a model execution API.
enum CanonicalBinaryState {
    enum CodingError: Error {
        case lengthOverflow
        case malformed
        case duplicateFunctionKey
    }

    static func encode(_ projection: TLAStateProjection) throws -> Data {
        var output = Data("STLASV01".utf8)
        let entries = projection.entries.sorted {
            $0.token.description.utf8.lexicographicallyPrecedes($1.token.description.utf8)
        }
        try appendCount(entries.count, to: &output)
        for entry in entries {
            try appendString(entry.token.description, to: &output)
            output.append(try encode(entry.value))
        }
        return output
    }

    static func validate(_ data: Data) throws {
        var cursor = Cursor(data: data)
        guard try cursor.take(8) == Data("STLASV01".utf8) else {
            throw CodingError.malformed
        }
        let count = try cursor.count()
        guard count <= (data.count - cursor.offset) / 9 else { throw CodingError.malformed }
        var previous: Data?
        for _ in 0..<count {
            let name = try cursor.stringBytes()
            guard previous.map({ $0.lexicographicallyPrecedes(name) }) ?? true else {
                throw CodingError.malformed
            }
            previous = name
            try cursor.value()
        }
        guard cursor.atEnd else { throw CodingError.malformed }
    }

    private struct Cursor {
        let data: Data
        var offset = 0
        var atEnd: Bool { offset == data.count }

        mutating func take(_ length: Int) throws -> Data {
            guard length >= 0, length <= data.count - offset else {
                throw CodingError.malformed
            }
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }

        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw CodingError.malformed }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func count() throws -> Int {
            let bytes = try take(4)
            return bytes.reduce(0) { ($0 << 8) | Int($1) }
        }

        mutating func stringBytes() throws -> Data {
            let length = try count()
            let bytes = try take(length)
            guard String(data: bytes, encoding: .utf8) != nil else {
                throw CodingError.malformed
            }
            return bytes
        }

        mutating func value() throws {
            let start = offset
            let tag = try byte()
            let length = try count()
            guard length <= data.count - offset else { throw CodingError.malformed }
            let end = offset + length
            switch tag {
            case 1:
                guard length == 8 else { throw CodingError.malformed }
                _ = try take(8)
            case 2:
                guard length == 1, try byte() <= 1 else { throw CodingError.malformed }
            case 3, 4:
                guard String(data: try take(length), encoding: .utf8) != nil else {
                    throw CodingError.malformed
                }
            case 5, 6:
                let members = try count()
                guard offset <= end, members <= (end - offset) / 5 else {
                    throw CodingError.malformed
                }
                var previous: Data?
                for _ in 0..<members {
                    let memberStart = offset
                    try value()
                    if tag == 5 {
                        let encoded = data.subdata(in: memberStart..<offset)
                        guard previous.map({ $0.lexicographicallyPrecedes(encoded) }) ?? true else {
                            throw CodingError.malformed
                        }
                        previous = encoded
                    }
                }
            case 7, 8:
                let members = try count()
                guard offset <= end, members > 0,
                      members <= (end - offset) / (tag == 7 ? 9 : 10) else {
                    throw CodingError.malformed
                }
                var previous: Data?
                for _ in 0..<members {
                    let fieldStart = offset
                    let field: Data
                    if tag == 7 {
                        field = try stringBytes()
                    } else {
                        try value()
                        field = data.subdata(in: fieldStart..<offset)
                    }
                    guard previous.map({ $0.lexicographicallyPrecedes(field) }) ?? true else {
                        throw CodingError.malformed
                    }
                    previous = field
                    try value()
                }
            default:
                throw CodingError.malformed
            }
            guard offset == end, offset > start else { throw CodingError.malformed }
        }
    }

    private static func encode(_ value: TLAValue) throws -> Data {
        var payload = Data()
        let tag: UInt8
        switch value {
        case .int(let integer):
            tag = 1
            appendUInt64(UInt64(bitPattern: Int64(integer)), to: &payload)
        case .bool(let boolean):
            tag = 2
            payload.append(boolean ? 1 : 0)
        case .string(let string):
            tag = 3
            payload.append(contentsOf: string.utf8)
        case .constant(let constant):
            tag = 4
            payload.append(contentsOf: constant.utf8)
        case .set(let members):
            tag = 5
            let ordered = try members.map(encode).sorted(by: { $0.lexicographicallyPrecedes($1) })
            var unique: [Data] = []
            unique.reserveCapacity(ordered.count)
            for member in ordered where unique.last != member { unique.append(member) }
            try appendCount(unique.count, to: &payload)
            for member in unique { payload.append(member) }
        case .tuple(let members):
            tag = 6
            try appendCount(members.count, to: &payload)
            for member in members { payload.append(try encode(member)) }
        case .record(let record):
            return try encodeRecord(record.fields.map { ($0.name, $0.value) })
        case .function(let mapping):
            if mapping.isEmpty { return try encode(.tuple([])) }
            let indexed = mapping.compactMap { key, value -> (Int, TLAValue)? in
                guard case .int(let index) = key else { return nil }
                return (index, value)
            }.sorted { $0.0 < $1.0 }
            if indexed.count == mapping.count,
               indexed.enumerated().allSatisfy({ $0.offset + 1 == $0.element.0 }) {
                return try encode(.tuple(indexed.map(\.1)))
            }
            let fields = mapping.compactMap { key, value -> (String, TLAValue)? in
                guard case .string(let name) = key else { return nil }
                return (name, value)
            }
            if fields.count == mapping.count { return try encodeRecord(fields) }
            tag = 8
            let entries = try mapping.map { (try encode($0.key), try encode($0.value)) }
                .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            for index in 1..<entries.count where entries[index - 1].0 == entries[index].0 {
                throw CodingError.duplicateFunctionKey
            }
            try appendCount(entries.count, to: &payload)
            for (key, value) in entries {
                payload.append(key)
                payload.append(value)
            }
        }
        return try wrap(tag: tag, payload: payload)
    }

    private static func encodeRecord(_ fields: [(String, TLAValue)]) throws -> Data {
        var payload = Data()
        if fields.isEmpty { return try encode(.tuple([])) }
        let ordered = fields.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
        try appendCount(ordered.count, to: &payload)
        for (name, value) in ordered {
            try appendString(name, to: &payload)
            payload.append(try encode(value))
        }
        return try wrap(tag: 7, payload: payload)
    }

    private static func wrap(tag: UInt8, payload: Data) throws -> Data {
        var output = Data([tag])
        try appendCount(payload.count, to: &output)
        output.append(payload)
        return output
    }

    private static func appendString(_ value: String, to output: inout Data) throws {
        try appendCount(value.utf8.count, to: &output)
        output.append(contentsOf: value.utf8)
    }

    private static func appendCount(_ count: Int, to output: inout Data) throws {
        guard let value = UInt32(exactly: count) else { throw CodingError.lengthOverflow }
        for shift in stride(from: 24, through: 0, by: -8) {
            output.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    private static func appendUInt64(_ value: UInt64, to output: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            output.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}

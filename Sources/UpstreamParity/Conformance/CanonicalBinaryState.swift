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
        output.reserveCapacity(512)
        var lengthPatches: [LengthPatch] = []
        let entries = projection.entries.sorted {
            $0.token.description.utf8.lexicographicallyPrecedes($1.token.description.utf8)
        }
        try appendCount(entries.count, to: &output)
        for entry in entries {
            try appendString(entry.token.description, to: &output)
            try encode(entry.value, to: &output, lengthPatches: &lengthPatches)
        }
        apply(lengthPatches, to: &output)
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
            return data[offset..<(offset + length)]
        }

        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw CodingError.malformed }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func count() throws -> Int {
            guard data.count - offset >= 4 else { throw CodingError.malformed }
            let value = (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16)
                | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            offset += 4
            return value
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
                offset += 8
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
                        let encoded = data[memberStart..<offset]
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
                        field = data[fieldStart..<offset]
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
        var output = Data()
        var lengthPatches: [LengthPatch] = []
        try encode(value, to: &output, lengthPatches: &lengthPatches)
        apply(lengthPatches, to: &output)
        return output
    }

    private static func encode(
        _ value: TLAValue, to output: inout Data, lengthPatches: inout [LengthPatch]
    ) throws {
        switch value {
        case .int(let integer):
            let lengthOffset = beginValue(tag: 1, to: &output)
            appendUInt64(UInt64(bitPattern: Int64(integer)), to: &output)
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .bool(let boolean):
            let lengthOffset = beginValue(tag: 2, to: &output)
            output.append(boolean ? 1 : 0)
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .string(let string):
            let lengthOffset = beginValue(tag: 3, to: &output)
            output.append(contentsOf: string.utf8)
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .constant(let constant):
            let lengthOffset = beginValue(tag: 4, to: &output)
            output.append(contentsOf: constant.utf8)
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .set(let members):
            let ordered = try members.map(encode).sorted(by: { $0.lexicographicallyPrecedes($1) })
            var unique: [Data] = []
            unique.reserveCapacity(ordered.count)
            for member in ordered where unique.last != member { unique.append(member) }
            let lengthOffset = beginValue(tag: 5, to: &output)
            try appendCount(unique.count, to: &output)
            for member in unique { output.append(member) }
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .tuple(let members):
            let lengthOffset = beginValue(tag: 6, to: &output)
            try appendCount(members.count, to: &output)
            for member in members {
                try encode(member, to: &output, lengthPatches: &lengthPatches)
            }
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        case .record(let record):
            try encodeRecord(record.fields.map { ($0.name, $0.value) }, to: &output,
                             lengthPatches: &lengthPatches)
        case .function(let mapping):
            if mapping.isEmpty {
                try encode(.tuple([]), to: &output, lengthPatches: &lengthPatches)
                return
            }
            let indexed = mapping.compactMap { key, value -> (Int, TLAValue)? in
                guard case .int(let index) = key else { return nil }
                return (index, value)
            }.sorted { $0.0 < $1.0 }
            if indexed.count == mapping.count,
               indexed.enumerated().allSatisfy({ $0.offset + 1 == $0.element.0 }) {
                try encode(.tuple(indexed.map(\.1)), to: &output,
                           lengthPatches: &lengthPatches)
                return
            }
            let fields = mapping.compactMap { key, value -> (String, TLAValue)? in
                guard case .string(let name) = key else { return nil }
                return (name, value)
            }
            if fields.count == mapping.count {
                try encodeRecord(fields, to: &output, lengthPatches: &lengthPatches)
                return
            }
            let lengthOffset = beginValue(tag: 8, to: &output)
            let entries = try mapping.map { (try encode($0.key), try encode($0.value)) }
                .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            for index in 1..<entries.count where entries[index - 1].0 == entries[index].0 {
                throw CodingError.duplicateFunctionKey
            }
            try appendCount(entries.count, to: &output)
            for (key, value) in entries {
                output.append(key)
                output.append(value)
            }
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        }
    }

    private static func encodeRecord(
        _ fields: [(String, TLAValue)], to output: inout Data,
        lengthPatches: inout [LengthPatch]
    ) throws {
        if fields.isEmpty {
            try encode(.tuple([]), to: &output, lengthPatches: &lengthPatches)
            return
        }
        let lengthOffset = beginValue(tag: 7, to: &output)
        let ordered = fields.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
        try appendCount(ordered.count, to: &output)
        for (name, value) in ordered {
            try appendString(name, to: &output)
            try encode(value, to: &output, lengthPatches: &lengthPatches)
        }
        try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
    }

    private static func beginValue(tag: UInt8, to output: inout Data) -> Int {
        output.append(tag)
        let lengthOffset = output.count
        output.append(contentsOf: [0, 0, 0, 0])
        return lengthOffset
    }

    private struct LengthPatch {
        let offset: Int
        let length: UInt32
    }

    private static func finishValue(
        lengthOffset: Int, in output: Data, patches: inout [LengthPatch]
    ) throws {
        guard let length = UInt32(exactly: output.count - lengthOffset - 4) else {
            throw CodingError.lengthOverflow
        }
        patches.append(LengthPatch(offset: lengthOffset, length: length))
    }

    private static func apply(_ patches: [LengthPatch], to output: inout Data) {
        output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for patch in patches {
                for index in 0..<4 {
                    bytes[patch.offset + index] = UInt8(truncatingIfNeeded:
                        patch.length >> (24 - index * 8))
                }
            }
        }
    }

    private static func appendString(_ value: String, to output: inout Data) throws {
        try appendCount(value.utf8.count, to: &output)
        output.append(contentsOf: value.utf8)
    }

    private static func appendCount(_ count: Int, to output: inout Data) throws {
        guard let value = UInt32(exactly: count) else { throw CodingError.lengthOverflow }
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }

    private static func appendUInt64(_ value: UInt64, to output: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { output.append(contentsOf: $0) }
    }
}

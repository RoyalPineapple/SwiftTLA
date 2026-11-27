import Foundation
import SwiftTLA

/// Versioned, complete value identity for parity evidence. This is a wire
/// contract between independent producers, not a model execution API.
enum CanonicalBinaryState {
    private static let fullVersion = Data("STLASV01".utf8)
    private static let viewVersion = Data("STLAVW01".utf8)

    static func isView(_ data: Data) -> Bool { data.prefix(8) == viewVersion }

    enum CodingError: Error {
        case lengthOverflow
        case malformed
        case duplicateFunctionKey
    }

    struct Encoder {
        private(set) var bytes = Data()
        private var lengthPatches: [LengthPatch] = []

        mutating func encode(_ projection: TLAStateProjection, viewed: Bool = false) throws {
            try CanonicalBinaryState.encode(projection, viewed: viewed,
                into: &bytes, lengthPatches: &lengthPatches)
        }

        /// The two wire records share values, but carry different headers and field orders.
        mutating func encode(_ full: TLAStateProjection, tupleView positions: [Int],
                             key: inout Encoder) throws {
            var ranges: [Range<Int>] = []
            try CanonicalBinaryState.encode(full, viewed: false, into: &bytes,
                lengthPatches: &lengthPatches) { ranges.append($0) }
            try encodeView(positions, ranges: ranges, key: &key)
        }

        mutating func encode(tupleView positions: [Int], key: inout Encoder,
                             visit: (inout TypedFields) throws -> Bool,
                             projection: () throws -> TLAStateProjection) throws {
            var fields = TypedFields()
            do {
                if try visit(&fields) {
                    fields.finish()
                    let ordered = fields.entries.sorted { $0.0.description.utf8.lexicographicallyPrecedes($1.0.description.utf8) }
                    bytes.removeAll(keepingCapacity: true)
                    bytes.append(fullVersion)
                    try appendCount(ordered.count, to: &bytes)
                    var ranges: [Range<Int>] = []
                    for (index, entry) in ordered.enumerated() {
                        guard index == 0 || entry.0 != ordered[index - 1].0 else { throw CodingError.malformed }
                        try appendString(entry.0.description, to: &bytes)
                        let start = bytes.count
                        bytes.append(fields.bytes[entry.1])
                        ranges.append(start..<bytes.count)
                    }
                    try encodeView(positions, ranges: ranges, key: &key)
                    return
                }
            } catch is TLAStateProjectionDiagnostic {
                // Materialization preserves source-order diagnostics, including nested paths.
            } catch is CodingError {
                // Distinct formal values can share canonical bytes. Resolve them through the projection.
            }
            try encode(projection(), tupleView: positions, key: &key)
        }

        private func encodeView(_ positions: [Int], ranges: [Range<Int>], key: inout Encoder) throws {
            key.bytes.removeAll(keepingCapacity: true)
            key.lengthPatches.removeAll(keepingCapacity: true)
            key.bytes.append(viewVersion)
            try appendCount(1, to: &key.bytes)
            try appendString("View", to: &key.bytes)
            let tuple = beginValue(tag: 6, to: &key.bytes)
            try appendCount(positions.count, to: &key.bytes)
            for position in positions {
                guard ranges.indices.contains(position) else { throw CodingError.malformed }
                key.bytes.append(bytes[ranges[position]])
            }
            try finishValue(lengthOffset: tuple, in: key.bytes, patches: &key.lengthPatches)
            apply(key.lengthPatches, to: &key.bytes)
        }
    }

    struct TypedFields: _NativeProjectionSink {
        fileprivate var entries: [(TLAStateProjection.Token, Range<Int>)] = []
        fileprivate var bytes = Data()
        private var patches: [LengthPatch] = []

        fileprivate mutating func finish() { apply(patches, to: &bytes) }
        mutating func field<T>(_ token: TLAStateProjection.Token, _ value: T, _ write: (T, inout Self) throws -> Void) throws {
            let start = bytes.count
            try write(value, &self)
            entries.append((token, start..<bytes.count))
        }

        mutating func projected(_ value: TLAValue) throws {
            try TLAStateProjection.validate(value, at: "")
            try CanonicalBinaryState.encode(value, to: &bytes, lengthPatches: &patches)
        }

        private mutating func container(_ tag: UInt8, count: Int, body: (inout Self) throws -> Void) throws {
            let offset = beginValue(tag: tag, to: &bytes)
            try appendCount(count, to: &bytes)
            try body(&self)
            try finishValue(lengthOffset: offset, in: bytes, patches: &patches)
        }

        mutating func record(_ layout: _NativeProjectionRecord, _ field: (Int, inout Self) throws -> Void) throws {
            guard let order = layout.canonicalOrder else { throw CodingError.malformed }
            try container(order.isEmpty ? 6 : 7, count: order.count) { out in
                for index in order {
                    try appendString(layout.names[index], to: &out.bytes)
                    try field(index, &out)
                }
            }
        }

        mutating func members<C: Collection & Sendable>(_ members: C, _ write: (C.Element, inout Self) throws -> Void) throws where C.Element: Sendable {
            let ordered = try members.map { member in
                var child = Self()
                try write(member, &child)
                child.finish()
                return child.bytes
            }.sorted { $0.lexicographicallyPrecedes($1) }
            try container(5, count: ordered.count) { out in
                for (index, member) in ordered.enumerated() {
                    guard index == 0 || member != ordered[index - 1] else { throw CodingError.malformed }
                    out.bytes.append(member)
                }
            }
        }

        mutating func constantFunction<S: Sequence, K, V>(_ entries: S, key: (K) throws -> TLAValue,
            value: (V, inout Self) throws -> Void) throws where S.Element == (key: K, value: V) {
            let ordered = try entries.map { entry in
                let index = try key(entry.key)
                guard case .constant(let name) = index, TLAStateProjection.Token(validating: name) != nil else {
                    throw CodingError.malformed
                }
                return (try CanonicalBinaryState.encode(index), entry.value)
            }.sorted { $0.0.lexicographicallyPrecedes($1.0) }
            try container(ordered.isEmpty ? 6 : 8, count: ordered.count) { out in
                for (index, entry) in ordered.enumerated() {
                    guard index == 0 || entry.0 != ordered[index - 1].0 else { throw CodingError.duplicateFunctionKey }
                    out.bytes.append(entry.0)
                    try value(entry.1, &out)
                }
            }
        }
    }

    static func encode(_ projection: TLAStateProjection, viewed: Bool = false) throws -> Data {
        var encoder = Encoder()
        try encoder.encode(projection, viewed: viewed)
        return encoder.bytes
    }

    private static func encode(
        _ projection: TLAStateProjection, viewed: Bool, into output: inout Data,
        lengthPatches: inout [LengthPatch],
        fieldEncoded: (Range<Int>) -> Void = { _ in }
    ) throws {
        output.removeAll(keepingCapacity: true)
        output.reserveCapacity(512)
        output.append(viewed ? viewVersion : fullVersion)
        lengthPatches.removeAll(keepingCapacity: true)
        let entries = projection.entries
        if viewed, entries.count != 1 || entries.first?.token.description != "View" {
            throw CodingError.malformed
        }
        try appendCount(entries.count, to: &output)
        for entry in entries {
            try appendString(entry.token.description, to: &output)
            let start = output.count
            try encode(entry.value, to: &output, lengthPatches: &lengthPatches)
            fieldEncoded(start..<output.count)
        }
        apply(lengthPatches, to: &output)
    }

    static func validate(_ data: Data) throws {
        var cursor = Cursor(data: data)
        let version = try cursor.take(8)
        guard version == fullVersion || version == viewVersion else {
            throw CodingError.malformed
        }
        let count = try cursor.count()
        if version == viewVersion && count != 1 { throw CodingError.malformed }
        guard count <= (data.count - cursor.offset) / 9 else { throw CodingError.malformed }
        var previous: Data?
        for _ in 0..<count {
            let name = try cursor.stringBytes()
            if version == viewVersion && name != Data("View".utf8) { throw CodingError.malformed }
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
            try encodeOrderedRecord(record.fields.map { ($0.name, $0.value) }, to: &output,
                             lengthPatches: &lengthPatches)
        case .function(let mapping):
            if mapping.isEmpty {
                try encode(.tuple([]), to: &output, lengthPatches: &lengthPatches)
                return
            }
            if let firstKey = mapping.first?.key {
                switch firstKey {
                case .int:
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
                case .string:
                    let fields = mapping.compactMap { key, value -> (String, TLAValue)? in
                        guard case .string(let name) = key else { return nil }
                        return (name, value)
                    }
                    if fields.count == mapping.count {
                        let ordered = fields.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
                        try encodeOrderedRecord(ordered, to: &output, lengthPatches: &lengthPatches)
                        return
                    }
                default:
                    break
                }
            }
            let lengthOffset = beginValue(tag: 8, to: &output)
            let entries = try mapping.map { (try encode($0.key), $0.value) }
                .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            for index in 1..<entries.count where entries[index - 1].0 == entries[index].0 {
                throw CodingError.duplicateFunctionKey
            }
            try appendCount(entries.count, to: &output)
            for (key, value) in entries {
                output.append(key)
                try encode(value, to: &output, lengthPatches: &lengthPatches)
            }
            try finishValue(lengthOffset: lengthOffset, in: output, patches: &lengthPatches)
        }
    }

    private static func encodeOrderedRecord(
        _ ordered: [(String, TLAValue)], to output: inout Data,
        lengthPatches: inout [LengthPatch]
    ) throws {
        if ordered.isEmpty {
            try encode(.tuple([]), to: &output, lengthPatches: &lengthPatches)
            return
        }
        let lengthOffset = beginValue(tag: 7, to: &output)
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

import CryptoKit
import Foundation

enum BinaryGraphEvidenceError: Error {
    case invalid(String)
}

struct BinaryGraphEvidenceWriter {
    private let handle: FileHandle
    private var buffer = Data()
    private var digest = CryptoKit.SHA256()
    private(set) var states = 0
    private(set) var initials = 0
    private(set) var edges = 0
    private(set) var violations = 0
    private(set) var deadlocks = 0
    private(set) var reachability = 0

    init(to url: URL, caseID: String) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(1_048_576)
        append(Data("STLAGRF2".utf8))
        byte(2)
        try string(caseID)
        try string("")
    }

    mutating func action(id: UInt32, name: String) throws {
        byte(1)
        uint32(id)
        try string(name)
        try string("")
        try flushIfNeeded()
    }

    mutating func state(id: UInt64, key: Data, initial: Bool) throws {
        byte(2)
        uint64(id)
        byte(initial ? 1 : 0)
        try bytes(key)
        states += 1
        if initial { initials += 1 }
        try flushIfNeeded()
    }

    mutating func edge(source: UInt64, action: UInt32, target: UInt64) throws {
        byte(3)
        uint64(source)
        uint32(action)
        uint64(target)
        edges += 1
        try flushIfNeeded()
    }

    mutating func invariantFailure(property: String, key: Data,
        predecessor: UInt64?, action: UInt32?) throws {
        byte(6)
        try string(property)
        try bytes(key)
        uint64(predecessor ?? UInt64.max)
        uint32(action ?? UInt32.max)
        violations += 1
        try flushIfNeeded()
    }

    mutating func deadlock(state: UInt64) throws {
        byte(7)
        uint64(state)
        deadlocks += 1
        try flushIfNeeded()
    }

    mutating func reached(property: String, key: Data,
        predecessor: UInt64?, action: UInt32?) throws {
        byte(8)
        try string(property)
        try bytes(key)
        uint64(predecessor ?? UInt64.max)
        uint32(action ?? UInt32.max)
        reachability += 1
        try flushIfNeeded()
    }

    mutating func finish(completion: UInt8) throws {
        try flush()
        let hash = Data(digest.finalize())
        byte(255)
        uint64(UInt64(states))
        uint64(UInt64(initials))
        uint64(UInt64(edges))
        uint64(0)
        uint64(0)
        uint64(UInt64(violations))
        uint64(UInt64(deadlocks))
        uint64(UInt64(reachability))
        byte(completion)
        append(hash)
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
        try handle.close()
    }

    mutating func close() {
        try? handle.close()
    }

    private mutating func byte(_ value: UInt8) { buffer.append(value) }

    private mutating func uint32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer.append(contentsOf: $0) }
    }

    private mutating func uint64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer.append(contentsOf: $0) }
    }

    private mutating func string(_ value: String) throws {
        guard let length = UInt32(exactly: value.utf8.count) else {
            throw BinaryGraphEvidenceError.invalid("string length")
        }
        uint32(length)
        buffer.append(contentsOf: value.utf8)
    }

    private mutating func bytes(_ value: Data) throws {
        guard let length = UInt32(exactly: value.count) else {
            throw BinaryGraphEvidenceError.invalid("byte length")
        }
        uint32(length)
        buffer.append(value)
    }

    private mutating func append(_ data: Data) { buffer.append(data) }

    private mutating func flushIfNeeded() throws {
        if buffer.count >= 1_048_576 { try flush() }
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        digest.update(data: buffer)
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

struct BinaryGraphEvidenceReader {
    private let handle: FileHandle
    private let fileSize: UInt64
    private let digestPrefixLength: UInt64?
    private var digest = CryptoKit.SHA256()
    private var digestedBytes: UInt64 = 0
    private var buffer = Data()
    private var cursor = 0
    private(set) var offset: UInt64 = 0

    init(_ url: URL, checksumFooterLength: UInt64? = nil) throws {
        handle = try FileHandle(forReadingFrom: url)
        fileSize = UInt64(try handle.seekToEnd())
        if let checksumFooterLength {
            guard checksumFooterLength <= fileSize else {
                throw BinaryGraphEvidenceError.invalid("truncated footer")
            }
            digestPrefixLength = fileSize - checksumFooterLength
        } else {
            digestPrefixLength = nil
        }
        try handle.seek(toOffset: 0)
    }

    var atEnd: Bool { offset == fileSize }

    mutating func byte() throws -> UInt8 {
        try ensure(1)
        let value = buffer[cursor]
        cursor += 1
        offset += 1
        return value
    }

    mutating func uint32() throws -> UInt32 {
        try ensure(4)
        let value = buffer.withUnsafeBytes {
            UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: cursor, as: UInt32.self))
        }
        cursor += 4
        offset += 4
        return value
    }

    mutating func uint16() throws -> UInt16 {
        try ensure(2)
        let value = buffer.withUnsafeBytes {
            UInt16(bigEndian: $0.loadUnaligned(fromByteOffset: cursor, as: UInt16.self))
        }
        cursor += 2
        offset += 2
        return value
    }

    mutating func uint64() throws -> UInt64 {
        try ensure(8)
        let value = buffer.withUnsafeBytes {
            UInt64(bigEndian: $0.loadUnaligned(fromByteOffset: cursor, as: UInt64.self))
        }
        cursor += 8
        offset += 8
        return value
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, UInt64(count) <= fileSize - offset else {
            throw BinaryGraphEvidenceError.invalid("record length")
        }
        try ensure(count)
        let result = Data(buffer[cursor..<(cursor + count)])
        cursor += count
        offset += UInt64(count)
        return result
    }

    mutating func string() throws -> String {
        let count = try Int(uint32())
        guard let value = String(data: try bytes(count), encoding: .utf8) else {
            throw BinaryGraphEvidenceError.invalid("UTF-8 string")
        }
        return value
    }

    mutating func close() { try? handle.close() }

    mutating func sha256Prefix(endingAt offset: UInt64) throws -> Data {
        guard digestPrefixLength == offset, digestedBytes == offset else {
            throw BinaryGraphEvidenceError.invalid("checksum prefix")
        }
        return Data(digest.finalize())
    }

    private mutating func ensure(_ count: Int) throws {
        guard UInt64(count) <= fileSize - offset else {
            throw BinaryGraphEvidenceError.invalid("truncated record")
        }
        while buffer.count - cursor < count {
            if cursor > 0 {
                buffer.removeSubrange(0..<cursor)
                cursor = 0
            }
            let chunk = try handle.read(upToCount: max(1_048_576, count - buffer.count)) ?? Data()
            guard !chunk.isEmpty else { throw BinaryGraphEvidenceError.invalid("truncated record") }
            if let digestPrefixLength, digestedBytes < digestPrefixLength {
                let length = Int(min(UInt64(chunk.count), digestPrefixLength - digestedBytes))
                digest.update(data: chunk.prefix(length))
                digestedBytes += UInt64(length)
            }
            buffer.append(chunk)
        }
    }
}

struct BinaryEdgeWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(1_048_576)
    }

    mutating func append(source: UInt64, action: UInt32, target: UInt64) throws {
        uint64(source)
        uint32(action)
        uint64(target)
        if buffer.count >= 1_048_576 { try flush() }
    }

    mutating func close() throws {
        try flush()
        try handle.close()
    }

    private mutating func uint32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer.append(contentsOf: $0) }
    }

    private mutating func uint64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer.append(contentsOf: $0) }
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

struct BinaryStateWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(1_048_576)
    }

    mutating func append(key: Data, id: UInt64, sortKey: UInt64) throws {
        guard let length = UInt32(exactly: key.count) else {
            throw BinaryGraphEvidenceError.invalid("state key length")
        }
        var bigEndianLength = length.bigEndian
        withUnsafeBytes(of: &bigEndianLength) { buffer.append(contentsOf: $0) }
        buffer.append(key)
        var bigEndianID = id.bigEndian
        withUnsafeBytes(of: &bigEndianID) { buffer.append(contentsOf: $0) }
        var bigEndianSortKey = sortKey.bigEndian
        withUnsafeBytes(of: &bigEndianSortKey) { buffer.append(contentsOf: $0) }
        if buffer.count >= 1_048_576 { try flush() }
    }

    mutating func close() throws {
        try flush()
        try handle.close()
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

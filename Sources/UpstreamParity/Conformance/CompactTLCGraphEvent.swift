import Foundation

/// Reads the exact, ordered JSON grammar emitted by LosslessStateWriter v4.
/// Unlike a general JSON object decoder, this does not allocate dictionaries
/// for millions of repeated transition records. Extra or repeated fields fail.
struct CompactTLCGraphEvent {
    struct State {
        let fingerprint: UInt64
        let bindings: [(name: String, tla: String)]?
    }

    struct Action {
        let name: String
        let location: String
        let named: Bool
    }

    enum Payload {
        case header
        case initial(State)
        case transition(source: UInt64, target: State, seen: Bool,
            excluded: Bool, rawFlags: Int, actions: [Action], predicate: String?, reachable: String)
        case unsupported(String)
        case footer(counts: [String: Int], lastBodySequence: Int, bodySHA256: String)
    }

    let runID: String
    let callback: String
    let payload: Payload

    static func parse(_ line: Data, caseID: String, expectedRunID: String?, sequence: Int) throws -> Self {
        var cursor = Cursor(bytes: Array(line))
        try cursor.literal("{\"schema\":\"swifttla.tlc.graph-events\",\"version\":4,\"type\":")
        let type = try cursor.string()
        try cursor.literal(",\"callback\":")
        let callback = try cursor.string()
        try cursor.literal(",\"seq\":")
        guard try cursor.integer() == sequence else { throw Error.invalid }
        try cursor.literal(",\"runId\":")
        let runID = try cursor.string()
        guard expectedRunID == nil ? UUID(uuidString: runID) != nil : expectedRunID == runID else {
            throw Error.invalid
        }
        try cursor.literal(",\"caseId\":")
        guard try cursor.string() == caseID else { throw Error.invalid }

        let payload: Payload
        switch type {
        case "header":
            guard callback == "writer.header", sequence == 0 else { throw Error.invalid }
            payload = .header
        case "initial":
            guard callback == "writeState.initial" else { throw Error.invalid }
            try cursor.literal(",\"state\":")
            payload = .initial(try cursor.state())
        case "transition":
            guard callback == "writeState.action" || callback == "writeState.actionPredicate" else {
                throw Error.invalid
            }
            try cursor.literal(",\"source\":")
            let source = try cursor.state()
            guard source.bindings == nil else { throw Error.invalid }
            try cursor.literal(",\"target\":")
            let target = try cursor.state()
            try cursor.literal(",\"action\":")
            _ = try cursor.action()
            try cursor.literal(",\"resolvedActions\":[")
            var actions: [Action] = []
            if !cursor.consume(93) {
                repeat { actions.append(try cursor.action()) } while cursor.consume(44)
                try cursor.literal("]")
            }
            try cursor.literal(",\"stateFlags\":{\"raw\":")
            let flags = try cursor.integer()
            try cursor.literal(",\"seen\":")
            let seen = try cursor.boolean()
            try cursor.literal(",\"notInModel\":")
            let excluded = try cursor.boolean()
            try cursor.literal("},\"visualization\":\"none\",\"predicateLocation\":")
            let predicate = cursor.consume(110) ? try cursor.nullRemainder() : try cursor.string()
            try cursor.literal(",\"reachable\":")
            let reachable = try cursor.string()
            payload = .transition(source: source.fingerprint, target: target, seen: seen,
                excluded: excluded, rawFlags: flags, actions: actions,
                predicate: predicate, reachable: reachable)
        case "unsupported":
            try cursor.literal(",\"reason\":")
            payload = .unsupported(try cursor.string())
        case "footer":
            guard callback == "writer.close" else { throw Error.invalid }
            try cursor.literal(",\"status\":\"closed\",\"counts\":{")
            var counts: [String: Int] = [:]
            if !cursor.consume(125) {
                repeat {
                    let name = try cursor.string()
                    try cursor.literal(":")
                    guard counts.updateValue(try cursor.integer(), forKey: name) == nil else {
                        throw Error.invalid
                    }
                } while cursor.consume(44)
                try cursor.literal("}")
            }
            try cursor.literal(",\"lastBodySeq\":")
            let last = try cursor.integer()
            try cursor.literal(",\"bodySha256\":")
            payload = .footer(counts: counts, lastBodySequence: last, bodySHA256: try cursor.string())
        default:
            throw Error.invalid
        }
        try cursor.literal("}")
        guard cursor.finished else { throw Error.invalid }
        return .init(runID: runID, callback: callback, payload: payload)
    }

    enum Error: Swift.Error { case invalid }

    private struct Cursor {
        let bytes: [UInt8]
        var offset = 0
        var finished: Bool { offset == bytes.count }

        mutating func literal(_ value: String) throws {
            let length = value.utf8.count
            guard bytes.count - offset >= length,
                  bytes[offset..<(offset + length)].elementsEqual(value.utf8) else {
                throw Error.invalid
            }
            offset += length
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard offset < bytes.count, bytes[offset] == byte else { return false }
            offset += 1
            return true
        }

        mutating func string() throws -> String {
            guard consume(34) else { throw Error.invalid }
            let start = offset
            var escaped = false
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == 34 {
                    let content = bytes[start..<(offset - 1)]
                    if !escaped {
                        guard !content.contains(where: { $0 < 32 }),
                              let value = String(bytes: content, encoding: .utf8) else { throw Error.invalid }
                        return value
                    }
                    let quoted = Data(bytes[(start - 1)..<offset])
                    guard let value = try JSONSerialization.jsonObject(with: quoted,
                        options: .fragmentsAllowed) as? String else { throw Error.invalid }
                    return value
                }
                if byte == 92 {
                    escaped = true
                    guard offset < bytes.count else { throw Error.invalid }
                    offset += 1
                }
            }
            throw Error.invalid
        }

        mutating func integer() throws -> Int {
            let start = offset
            var value = 0
            var digits = 0
            while offset < bytes.count, bytes[offset] >= 48, bytes[offset] <= 57 {
                let (scaled, overflow) = value.multipliedReportingOverflow(by: 10)
                let (next, carry) = scaled.addingReportingOverflow(Int(bytes[offset] - 48))
                guard !overflow, !carry else { throw Error.invalid }
                value = next
                offset += 1
                digits += 1
            }
            guard digits > 0, digits == 1 || bytes[start] != 48 else { throw Error.invalid }
            return value
        }

        mutating func fingerprint() throws -> UInt64 {
            guard consume(34) else { throw Error.invalid }
            var value: UInt64 = 0
            var digits = 0
            while offset < bytes.count, bytes[offset] >= 48, bytes[offset] <= 57 {
                let digit = UInt64(bytes[offset] - 48)
                let (scaled, overflow) = value.multipliedReportingOverflow(by: 10)
                let (next, carry) = scaled.addingReportingOverflow(digit)
                guard !overflow, !carry else { throw Error.invalid }
                value = next
                offset += 1
                digits += 1
            }
            guard digits > 0, consume(34) else { throw Error.invalid }
            return value
        }

        mutating func boolean() throws -> Bool {
            if consume(116) { try literal("rue"); return true }
            try literal("false")
            return false
        }

        mutating func nullRemainder() throws -> String? {
            try literal("ull")
            return nil
        }

        mutating func state() throws -> State {
            try literal("{\"fingerprint\":")
            let fingerprint = try fingerprint()
            try literal(",\"level\":")
            _ = try integer()
            if consume(125) { return State(fingerprint: fingerprint, bindings: nil) }
            try literal(",\"bindings\":[")
            var bindings: [(name: String, tla: String)] = []
            if !consume(93) {
                repeat {
                    try literal("{\"ordinal\":")
                    guard try integer() == bindings.count else { throw Error.invalid }
                    try literal(",\"name\":")
                    let name = try string()
                    try literal(",\"tla\":")
                    let tla = try string()
                    try literal("}")
                    bindings.append((name: name, tla: tla))
                } while consume(44)
                try literal("]")
            }
            try literal("}")
            return State(fingerprint: fingerprint, bindings: bindings)
        }

        mutating func action() throws -> Action {
            try literal("{\"name\":")
            let name = try string()
            try literal(",\"location\":")
            let location = try string()
            try literal(",\"named\":")
            let named = try boolean()
            try literal("}")
            return Action(name: name, location: location, named: named)
        }
    }
}

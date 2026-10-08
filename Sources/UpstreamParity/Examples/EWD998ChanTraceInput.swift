import Foundation

/// The external implementation log consumed by EWD998ChanTrace, before it is
/// matched against the model's transitions.
package struct EWD998ChanTraceInput: Sendable {
    package enum EventKind: String, Decodable, Sendable {
        case receive = "<"
        case send = ">"
        case deactivate = "d"
    }

    package enum MessageKind: String, Decodable, Sendable {
        case token = "tok"
        case payload = "pl"
        case terminate = "trm"
    }

    package struct Message: Decodable, Sendable {
        package let type: MessageKind
        package let q: Int?
        package let color: EWD998ChanModel.Color?

        enum CodingKeys: String, CodingKey { case type, q, color }

        package init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(MessageKind.self, forKey: .type)
            q = try values.decodeIfPresent(Int.self, forKey: .q)
            if let name = try values.decodeIfPresent(String.self, forKey: .color) {
                guard let parsed = EWD998ChanModel.Color(rawValue: name) else {
                    throw DecodingError.dataCorruptedError(forKey: .color, in: values,
                        debugDescription: "unknown token color")
                }
                color = parsed
            } else {
                color = nil
            }
        }
    }

    package struct Event: Sendable {
        package let kind: EventKind
        package let node: Int
        package let sender: Int?
        package let receiver: Int?
        package let message: Message?
        package let clock: [Int: Int]
        package let hasFailure: Bool
        package let sourceLine: Int
    }

    package enum InputError: Error, Equatable {
        case missingHeader
        case invalidHeader
        case invalidEvent(Int)
    }

    package let nodeCount: Int
    package let events: [Event]

    package init(ndjson: Data) throws {
        let lines = ndjson.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard let first = lines.first, !first.isEmpty else { throw InputError.missingHeader }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: Data(first)), header.N > 0 else {
            throw InputError.invalidHeader
        }
        let nodeCount = header.N
        self.nodeCount = nodeCount
        let eventLines = Array(lines.dropFirst().enumerated())
        var parsed: [Event] = []
        parsed.reserveCapacity(eventLines.count)
        for (offset, line) in eventLines {
            let sourceLine = offset + 2
            if line.isEmpty {
                guard offset == eventLines.count - 1 else { throw InputError.invalidEvent(sourceLine) }
                continue
            }
            guard let entry = try? decoder.decode(LogEntry.self, from: Data(line)),
                  (0..<nodeCount).contains(entry.node) else { throw InputError.invalidEvent(sourceLine) }
            let packet = entry.packet
            var clock: [Int: Int] = [:]
            for (key, value) in packet.vc {
                guard let node = Int(key), String(node) == key,
                      (0..<nodeCount).contains(node), value >= 0 else {
                    throw InputError.invalidEvent(sourceLine)
                }
                clock[node] = value
            }
            let hasMessage = entry.kind != .deactivate
            guard hasMessage == (packet.msg != nil),
                  hasMessage == (packet.snd != nil && packet.rcv != nil),
                  packet.msg?.type != .token || (packet.msg?.q != nil && packet.msg?.color != nil)
            else { throw InputError.invalidEvent(sourceLine) }
            if let sender = packet.snd, let receiver = packet.rcv {
                guard (0..<nodeCount).contains(sender), (0..<nodeCount).contains(receiver) else {
                    throw InputError.invalidEvent(sourceLine)
                }
            }
            parsed.append(Event(kind: entry.kind, node: entry.node,
                                sender: packet.snd, receiver: packet.rcv,
                                message: packet.msg, clock: clock,
                                hasFailure: entry.hasFailure, sourceLine: sourceLine))
        }
        events = parsed
    }

    private struct Header: Decodable { let N: Int }

    private struct LogEntry: Decodable {
        let kind: EventKind
        let node: Int
        let packet: Packet
        let hasFailure: Bool

        enum CodingKeys: String, CodingKey { case event, node, pkt, failure }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            hasFailure = values.contains(.failure)
            kind = try values.decode(EventKind.self, forKey: .event)
            node = try values.decode(Int.self, forKey: .node)
            packet = try values.decode(Packet.self, forKey: .pkt)
        }
    }

    private struct Packet: Decodable {
        let snd: Int?
        let rcv: Int?
        let msg: Message?
        let vc: [String: Int]
    }

}

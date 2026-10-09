import Foundation
import Testing
@testable import UpstreamParity

struct EWD998ChanTraceReferenceTests {
    @Test("the retained TLC order maps full log records back to every source line")
    func selectedCausalOrder() throws {
        let log = Data("""
        {"N":2}
        {"event":"d","node":0,"pkt":{"vc":{"0":1}}}
        {"event":"d","node":1,"pkt":{"vc":{"1":1}}}
        """.utf8)
        let input = try EWD998ChanTraceInput(ndjson: log)
        let printed = try TLCValueParser.parse("""
        <<[event |-> "d", node |-> 1, pkt |-> [vc |-> [1 |-> 1]]],
          [event |-> "d", node |-> 0, pkt |-> [vc |-> [0 |-> 1]]]>>
        """)
        #expect(try EWD998ChanTraceReference.sourceLines(
            in: log, orderedBy: printed, input: input) == [3, 2])
        let duplicated = try TLCValueParser.parse("""
        <<[event |-> "d", node |-> 1, pkt |-> [vc |-> [1 |-> 1]]],
          [event |-> "d", node |-> 1, pkt |-> [vc |-> [1 |-> 1]]]>>
        """)
        #expect(throws: EvidenceFormatError.invalidField(
            record: "ewd998-chan-trace", field: "printed trace-log event")) {
            try EWD998ChanTraceReference.sourceLines(
                in: log, orderedBy: duplicated, input: input)
        }
    }
}

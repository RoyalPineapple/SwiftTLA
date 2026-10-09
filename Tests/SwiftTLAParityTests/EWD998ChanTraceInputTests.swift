import Foundation
import Testing
@testable import UpstreamParity

struct EWD998ChanTraceInputTests {
    @Test("the pinned implementation log retains all unordered typed events")
    func pinnedImplementationLog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let input = try EWD998ChanTraceInput(ndjson: Data(contentsOf:
            root.appendingPathComponent("Verification/FiniteGraph/fixtures/ewd998/EWD998ChanTrace.ndjson")))
        #expect(input.nodeCount == 5)
        #expect(input.events.count == 654)
        #expect(input.events.map(\.sourceLine) == Array(2...655))
        #expect(input.events.first?.sourceLine == 2)
        #expect(input.events[0].kind == .receive)
        #expect(input.events[0].clock == [0: 1])
        #expect(input.events[1].clock[4] == 91)
        let failures = input.events.filter { $0.hasFailure }
        #expect(failures.isEmpty)
        #expect(throws: EWD998ChanTraceInput.InputError.causalityViolation(earlier: 3, later: 4)) {
            try input.events(inCausalOrder: input.events.map(\.sourceLine))
        }
        let orderData = try Data(contentsOf: root.appendingPathComponent(
            "Verification/FiniteGraph/fixtures/ewd998/EWD998ChanTrace.selected-order.json"))
        #expect(orderData.last == 0x0A)
        #expect(SHA256.hex(Data(orderData.dropLast())) ==
            "b728a7eac858354dc10d2bc4616ba68fcca724ca141a1890e5bf0c5dec6af6eb")
        let order = try JSONDecoder().decode([Int].self, from: orderData)
        #expect(try input.events(inCausalOrder: order).count == 654)
    }

    @Test("invalid input fails closed while a reported failure remains an event")
    func malformedLog() {
        #expect(throws: EWD998ChanTraceInput.InputError.invalidHeader) {
            try EWD998ChanTraceInput(ndjson: Data("{\"N\":0}\n".utf8))
        }
        let failure = """
        {"N":1}
        {"event":"d","node":0,"pkt":{"vc":{"0":1}},"failure":null}
        """
        let reported = try? EWD998ChanTraceInput(ndjson: Data(failure.utf8))
        #expect(reported?.events.first?.hasFailure == true)
    }

    @Test("causal-order validation preserves concurrent choices and rejects missing or reversed events")
    func validatesSelectedCausalOrder() throws {
        let log = """
        {"N":2}
        {"event":"d","node":0,"pkt":{"vc":{"0":1}}}
        {"event":"d","node":1,"pkt":{"vc":{"1":1}}}
        {"event":"d","node":0,"pkt":{"vc":{"0":2,"1":2}}}
        """
        let input = try EWD998ChanTraceInput(ndjson: Data(log.utf8))
        #expect(try input.events(inCausalOrder: [2, 3, 4]).map(\.sourceLine) == [2, 3, 4])
        #expect(try input.events(inCausalOrder: [3, 2, 4]).map(\.sourceLine) == [3, 2, 4])
        #expect(throws: EWD998ChanTraceInput.InputError.incompleteCausalOrder) {
            try input.events(inCausalOrder: [2, 2, 4])
        }
        #expect(throws: EWD998ChanTraceInput.InputError.causalityViolation(earlier: 4, later: 2)) {
            try input.events(inCausalOrder: [4, 2, 3])
        }
    }
}

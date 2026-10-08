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
}

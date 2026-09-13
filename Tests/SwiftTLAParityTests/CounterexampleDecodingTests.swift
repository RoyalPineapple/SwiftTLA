import Foundation
import Testing
import UpstreamParity

struct CounterexampleDecodingTests {
    @Test("loop-back positions retain numbered occurrences even when state values repeat")
    func retainsExactLoopOccurrence() throws {
        let first: [Any] = [1, ["x": 0]]
        let second: [Any] = [2, ["x": 1]]
        let third: [Any] = [3, ["x": 0]]
        let trace = try TLCTraceParser().parseCounterexample(JSONSerialization.data(withJSONObject: [
            "vars": ["x"], "counterexample": [
                "state": [first, second, third],
                "action": [[first, ["name": "A"], second], [second, ["name": "B"], third],
                           [third, ["name": "Stay"], third]]
            ]
        ]))
        #expect(trace.cycleStartIndex == 2)
        #expect(trace.steps.map(\.action) == [nil, "A", "B", "Stay"])
        #expect(trace.steps[0].state == trace.steps[2].state)
    }

    @Test("trace ordinals reject booleans and fractional numbers instead of truncating them")
    func rejectsInvalidOrdinals() throws {
        for ordinal: Any in [true, 1.5] {
            let invalid: [Any] = [ordinal, ["x": 0]]
            let valid: [Any] = [1, ["x": 0]]
            let inputs: [[String: Any]] = [
                ["vars": ["x"], "counterexample": ["state": [invalid], "action": []]],
                ["vars": ["x"], "counterexample": ["state": [valid],
                    "action": [[valid, ["name": "A"], invalid]]]]
            ]
            for input in inputs {
                #expect(throws: TLCTraceError.self) {
                    try TLCTraceParser().parseCounterexample(JSONSerialization.data(withJSONObject: input))
                }
            }
        }
    }

    @Test("excess action records fail before indexing the numbered states")
    func rejectsExcessActions() throws {
        let state: [Any] = [1, ["x": 0]]
        let action: [Any] = [state, ["name": "A"], state]
        let data = try JSONSerialization.data(withJSONObject: ["vars": ["x"],
            "counterexample": ["state": [state], "action": [action, action]]])
        #expect(throws: TLCTraceError.invalidAction(2)) {
            try TLCTraceParser().parseCounterexample(data)
        }
    }

    @Test("decoded canonical traces reject malformed cycles and state-changing stutters")
    func rejectsMalformedCanonicalTraces() throws {
        let first = CanonicalState(bindings: ["x": .integer(0)]).key
        let second = CanonicalState(bindings: ["x": .integer(1)]).key
        let traces = [
            GraphTrace(id: "empty", steps: []),
            GraphTrace(id: "initial-action", steps: [.init(state: first, action: "A")]),
            GraphTrace(id: "bad-index", steps: [.init(state: first, action: nil)], cycleStartIndex: 1),
            GraphTrace(id: "open-cycle", steps: [.init(state: first, action: nil),
                .init(state: second, action: "A")], cycleStartIndex: 0),
            GraphTrace(id: "changing-stutter", steps: [.init(state: first, action: nil),
                .init(state: second, action: nil)])
        ]
        for trace in traces {
            #expect(throws: GraphRunError.self) {
                try JSONDecoder().decode(GraphTrace.self, from: JSONEncoder().encode(trace))
            }
        }
    }
}

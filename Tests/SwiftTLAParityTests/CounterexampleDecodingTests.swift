import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct CounterexampleDecodingTests {
    @Test("parameterized TLC witnesses retain invocation identity through graph binding")
    func bindsParameterizedActions() throws {
        let states = [0, 1].map { CanonicalState(bindings: ["x": .integer($0)]) }
        let actions = [
            RenderedAction(sourceName: "advance", arguments: [.string("only"), .int(1)], renderedName: "advance__0"),
            RenderedAction(sourceName: "advance", arguments: [.string("other"), .int(1)], renderedName: "advance__1")
        ]
        let data = try actionTrace(["name": "advance", "parameters": ["_process", "amount"],
            "context": ["amount": 1, "_process": "only"]])
        let trace = try TLCTraceParser().parseCounterexample(data, states: states, renderedActions: actions)
        #expect(trace.steps.map(\.action) == [nil, "advance__0"])
        let graph = try CanonicalGraph(initialStates: [states[0]], states: states,
            edges: [CanonicalEdge(source: states[0].key, action: "advance__0", target: states[1].key)])
        try trace.validate(in: graph)
        #expect(throws: TLCTraceError.invalidAction(0)) {
            try TLCTraceParser().parseCounterexample(data, states: states)
        }
        for context: [String: Any] in [["amount": true, "_process": "only"],
            ["amount": 1, "_process": "unknown"], ["amount": 1]] {
            #expect(throws: TLCTraceError.invalidAction(0)) {
                try TLCTraceParser().parseCounterexample(actionTrace(["name": "advance",
                    "parameters": ["_process", "amount"], "context": context]), states: states, renderedActions: actions)
            }
        }
    }

    @Test("erased or malformed action arguments never select an arbitrary invocation")
    func rejectsAmbiguousActions() throws {
        let states = [0, 1].map { CanonicalState(bindings: ["x": .integer($0)]) }
        let actions = [
            RenderedAction(sourceName: "advance", arguments: [.string("only")], renderedName: "stringAction"),
            RenderedAction(sourceName: "advance", arguments: [.constant("only")], renderedName: "modelAction")
        ]
        #expect(throws: TLCTraceError.ambiguousAction(0)) {
            try TLCTraceParser().parseCounterexample(actionTrace(["name": "advance", "parameters": ["p"],
                "context": ["p": "only"]]), states: states, renderedActions: actions)
        }
        for metadata: [String: Any] in [
            ["name": "advance", "parameters": ["p", "p"], "context": ["p": "only"]],
            ["name": "advance", "parameters": ["p"]],
            ["name": "advance", "parameters": "p", "context": ["p": "only"]]
        ] {
            #expect(throws: TLCTraceError.invalidAction(0)) {
                try TLCTraceParser().parseCounterexample(actionTrace(metadata), states: states, renderedActions: actions)
            }
        }
    }

    private func actionTrace(_ metadata: [String: Any]) throws -> Data {
        let first: [Any] = [1, ["x": 0]]
        let second: [Any] = [2, ["x": 1]]
        return try JSONSerialization.data(withJSONObject: ["vars": ["x"], "counterexample": [
            "state": [first, second], "action": [[first, metadata, second]]]])
    }

    @Test("counterexample strings and record keys bind by their exact encoding")
    func bindsExactUnicodeValues() throws {
        let composed = "é"
        let decomposed = "e\u{301}"
        let cases: [(CanonicalValue, CanonicalValue, Any)] = [
            (.string(composed), .string(decomposed), composed),
            (.record([composed: .integer(1)]), .record([decomposed: .integer(1)]), [composed: 1])
        ]
        for (expected, foreign, json) in cases {
            let matching = CanonicalState(bindings: ["value": expected])
            let different = CanonicalState(bindings: ["value": foreign])
            let data = try JSONSerialization.data(withJSONObject: ["vars": ["value"],
                "counterexample": ["state": [[1, ["value": json]]], "action": []]])
            let trace = try TLCTraceParser().parseCounterexample(data, states: [different, matching])
            #expect(trace.steps.map(\.state) == [matching.key])
            #expect(throws: TLCTraceError.invalidState(0)) {
                try TLCTraceParser().parseCounterexample(data, states: [different])
            }
        }
    }

    @Test("TLC built-in stuttering requires a valid marker and unchanged state")
    func validatesBuiltInStuttering() throws {
        let first: [Any] = [1, ["x": 0]]
        let second: [Any] = [2, ["x": 1]]
        let states = [0, 1].map { CanonicalState(bindings: ["x": .integer($0)]) }
        for coordinate: Any in [0, 1, false, 0.5] {
            let metadata: [String: Any] = ["name": "UnnamedAction", "location": [
                "module": "--TLA+ BUILTINS--", "beginLine": coordinate,
                "beginColumn": 0, "endLine": 0, "endColumn": 0
            ]]
            for changesState in [false, true] {
                let data = try JSONSerialization.data(withJSONObject: ["vars": ["x"], "counterexample": [
                    "state": changesState ? [first, second] : [first],
                    "action": [[first, metadata, changesState ? second : first]]]])
                if !changesState, type(of: coordinate) == Int.self, coordinate as? Int == 0 {
                    let trace = try TLCTraceParser().parseCounterexample(data, states: states)
                    #expect(trace.steps.map(\.action) == [nil, nil])
                } else {
                    #expect(throws: TLCTraceError.invalidAction(0)) {
                        try TLCTraceParser().parseCounterexample(data, states: states)
                    }
                }
            }
        }
    }

    @Test("Trace binding preserves typed collections and model values erased by JSON")
    func bindsTypedValues() throws {
        let nested = CanonicalValue.set([
            .set([.integer(1), .integer(2)]), .tuple([.integer(1), .integer(2)])
        ])
        let function = try CanonicalValue.function([
            .init(key: .integer(0), value: .constant("nodeA")),
            .init(key: .boolean(true), value: .set([.integer(2), .integer(1)]))
        ])
        let examples: [(CanonicalValue, Any)] = [
            (nested, [[1, 2], [2, 1]]),
            (function, ["0": "nodeA", "TRUE": [1, 2]] as [String: Any]),
            (.record(["items": .set([]), "name": .constant("nodeA")]),
                ["items": [], "name": "nodeA"] as [String: Any]),
            (.tuple([]), [:] as [String: Any]),
            (.tuple([]), [] as [Any]),
            (.integer(Int.max), Int.max)
        ]
        for (value, json) in examples {
            let state = CanonicalState(bindings: ["value": value])
            let data = try JSONSerialization.data(withJSONObject: ["vars": ["value"],
                "counterexample": ["state": [[1, ["value": json]]], "action": []]])
            let trace = try TLCTraceParser().parseCounterexample(data, states: [state])
            #expect(trace.steps.map(\.state) == [state.key])
        }
    }

    @Test("Erased JSON identities must resolve to exactly one graph state")
    func rejectsAmbiguousValues() throws {
        let data = Data(#"{"vars":["value"],"counterexample":{"state":[[1,{"value":[1]}]],"action":[]}}"#.utf8)
        let states = [CanonicalValue.set([.integer(1)]), .tuple([.integer(1)])]
            .map { CanonicalState(bindings: ["value": $0]) }
        #expect(throws: TLCTraceError.ambiguousState(0)) {
            try TLCTraceParser().parseCounterexample(data, states: states)
        }
    }

    @Test("Duplicate set members, numeric overflow, and malformed JSON never bind a state")
    func rejectsInvalidValues() throws {
        let values: [(String, CanonicalValue)] = [
            ("[1,1]", .set([.integer(1), .integer(2)])),
            ("18446744073709551615", .integer(-1)),
            ("true", .integer(1)),
            ("1.5", .integer(1))
        ]
        for (json, value) in values {
            let data = Data("{\"vars\":[\"value\"],\"counterexample\":{\"state\":[[1,{\"value\":\(json)}]],\"action\":[]}}".utf8)
            #expect(throws: TLCTraceError.invalidState(0)) {
                try TLCTraceParser().parseCounterexample(data, states: [CanonicalState(bindings: ["value": value])])
            }
        }
        let duplicate = Data(#"{"vars":["value"],"counterexample":{"state":[[1,{"value":0,"value":1}]],"action":[]}}"#.utf8)
        #expect(throws: TLCTraceError.malformedJSON) {
            try TLCTraceParser().parseCounterexample(duplicate, states: [CanonicalState(bindings: ["value": .integer(1)])])
        }
    }

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
        ]), states: [0, 1].map { CanonicalState(bindings: ["x": .integer($0)]) })
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
                    try TLCTraceParser().parseCounterexample(JSONSerialization.data(withJSONObject: input),
                        states: [CanonicalState(bindings: ["x": .integer(0)])])
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
            try TLCTraceParser().parseCounterexample(data, states: [CanonicalState(bindings: ["x": .integer(0)])])
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

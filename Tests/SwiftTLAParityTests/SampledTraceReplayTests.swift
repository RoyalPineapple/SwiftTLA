import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct SampledTraceReplayTests {
    @Test("a sampled TLC initial state replays even when Swift sampled another valid state")
    func replaysIndependentRandomInitialState() throws {
        let initial = try RandomizedInitialReplay.initialMachines()
        let sampled = try #require(initial.first)
        #expect(initial.count == 1)
        let selected = sampled.state.x == 0 ? 1 : 0
        let trace = Data("{\"vars\":[\"x\"],\"counterexample\":{\"state\":[[1,{\"x\":\(selected)}]],\"action\":[]}}".utf8)
        let replay = try TLCTraceParser().replaySampledCounterexample(
            trace, initialMachines: initial, renderedActions: [],
            maximumDepth: 1, checkingDeadlock: false)
        #expect(replay.final.state.x == selected)

        let invalid = Data(#"{"vars":["x"],"counterexample":{"state":[[1,{"x":2}]],"action":[]}}"#.utf8)
        #expect(throws: TLCTraceError.invalidState(0)) {
            try TLCTraceParser().replaySampledCounterexample(
                invalid, initialMachines: initial, renderedActions: [],
                maximumDepth: 1, checkingDeadlock: false)
        }
    }

    @Test("sampled replay reconstructs typed functions and records from TLC JSON")
    func replaysRandomFunctionInitialState() throws {
        let initial = try RandomizedFunctionReplay.initialMachines()
        let sampled = try #require(initial.first)
        #expect(initial.count == 1)
        let choices = (0..<4).map { bits in
            [1: bits & 1 != 0, 2: bits & 2 != 0]
        }
        let selected = try #require(choices.first { $0 != sampled.state.samples })
        let mappingChoices = (0..<4).map { bits in
            [0: bits & 1 != 0, 2: bits & 2 != 0]
        }
        let selectedMapping = try #require(mappingChoices.first { $0 != sampled.state.mapping })
        func trace(_ sequence: [Bool], mapping: [String: Bool]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "vars": ["samples", "mapping", "token"],
                "counterexample": ["state": [[1, ["samples": sequence,
                    "mapping": mapping,
                    "token": ["pos": 0, "color": "white"]]]], "action": []]
            ])
        }
        let sequence = [selected[1]!, selected[2]!]
        let mapping = Dictionary(uniqueKeysWithValues: selectedMapping.map { (String($0.key), $0.value) })
        let replay = try TLCTraceParser().replaySampledCounterexample(
            trace(sequence, mapping: mapping), initialMachines: initial, renderedActions: [],
            maximumDepth: 1, checkingDeadlock: false)
        #expect(replay.final.state.samples == selected)
        #expect(replay.final.state.mapping == selectedMapping)
        #expect(replay.final.state.token.color == .white)

        let invalid = sequence + [false]
        #expect(throws: TLCTraceError.invalidState(0)) {
            try TLCTraceParser().replaySampledCounterexample(
                trace(invalid, mapping: mapping), initialMachines: initial, renderedActions: [],
                maximumDepth: 1, checkingDeadlock: false)
        }
        var invalidMapping = mapping
        invalidMapping["1"] = false
        #expect(throws: TLCTraceError.invalidState(0)) {
            try TLCTraceParser().replaySampledCounterexample(
                trace(sequence, mapping: invalidMapping), initialMachines: initial, renderedActions: [],
                maximumDepth: 1, checkingDeadlock: false)
        }
    }

    @Test("sampled TLC traces replay as bounded generated-machine paths")
    func replaysBoundedPath() throws {
        let initial = try TraceReplayCounter.initialMachines()
        let actions = try TraceReplayCounter.render().actions
        let data = try decisiveTraceData()
        let replay = try TLCTraceParser().replaySampledCounterexample(
            data, initialMachines: initial, renderedActions: actions,
            maximumDepth: 3, checkingDeadlock: false)
        #expect(replay.trace.steps.count == 4)
        #expect(replay.final.state.x == 3)
        #expect(throws: TLCTraceError.self) {
            try TLCTraceParser().replaySampledCounterexample(
                data, initialMachines: initial, renderedActions: actions,
                maximumDepth: 2, checkingDeadlock: false)
        }
        let altered = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"Next\"", with: "\"Unknown\"")
        #expect(throws: TLCTraceError.self) {
            try TLCTraceParser().replaySampledCounterexample(
                Data(altered.utf8), initialMachines: initial, renderedActions: actions,
                maximumDepth: 3, checkingDeadlock: false)
        }
    }
}

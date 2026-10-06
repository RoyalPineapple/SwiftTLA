import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct SampledTraceReplayTests {
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

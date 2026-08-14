import Testing
@testable import SwiftTLADemos

struct MediaPipelineDemoTests {
    @Test("pipeline permits playback only after a completed recording")
    func playbackFollowsRecording() throws {
        var machine = MediaPipeline()

        try MediaPipeline.verifySpec()
        try MediaPipeline.verifyTransitions()
        try MediaPipeline.verifyInvariants()

        _ = try machine.apply(.transition(process: .configureCapture))
        _ = try machine.apply(.transition(process: .configureWriter))
        _ = try machine.apply(.transition(process: .startRecording))
        _ = try machine.apply(.transition(process: .stopRecording))
        _ = try machine.apply(.transition(process: .preparePlayback))
        _ = try machine.apply(.transition(process: .play))

        #expect(machine.state.pipeline[MediaPipeline.PipelineSchema.player] == .playing)
    }
}

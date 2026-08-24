import AVPipeline

/// A hardware-free integration check for the AV formal models.
/// It executes representative generated lifecycles.
@main
struct AVPipelineCLI {
    static func main() async throws {
        var capture = try CaptureModel.makeMachine()
        var pipeline = try MediaPipelineModel.makeMachine()

        _ = try capture.send(.configure)
        _ = try capture.send(.start)
        _ = try capture.send(.stop)
        _ = try pipeline.send(.beginCapture)
        _ = try pipeline.send(.beginWriting)
        _ = try pipeline.send(.finishWriting)
        _ = try pipeline.send(.play)
        _ = try pipeline.send(.stop)

        print("AV pipeline typed machine checks passed.")
        print("capture: \(capture.state.phase.rawValue)")
        print("pipeline: \(pipeline.state.stage.rawValue)")
    }
}

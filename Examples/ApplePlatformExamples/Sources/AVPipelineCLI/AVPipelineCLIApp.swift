import AVPipeline

/// A hardware-free integration check for the AV component machines.
@main
struct AVPipelineCLI {
    static func main() async throws {
        var capture = try CaptureModel.makeMachine()

        _ = try capture.send(.configure)
        _ = try capture.send(.start)
        _ = try capture.send(.stop)

        print("AV component typed machine checks passed.")
        print("capture: \(capture.state.phase.rawValue)")
    }
}

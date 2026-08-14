import AVPipeline

/// A hardware-free integration check for the AV formal models.
/// It model-checks every spec and reports each generated initial state.
@main
struct AVPipelineCLI {
    static func main() async throws {
        try CaptureModel.verifySpec()
        try WriterModel.verifySpec()
        try PlayerModel.verifySpec()
        try DiskStoreModel.verifySpec()
        try MediaPipelineModel.verifySpec()

        let capture = CaptureModel.Machine()
        let pipeline = MediaPipelineModel.Machine()

        print("AV pipeline formal checks passed.")
        print("capture: \(await capture.state.phase.rawValue)")
        print("pipeline: \(await pipeline.state.stage.rawValue)")
    }
}

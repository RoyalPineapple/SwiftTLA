import AVPipeline

/// A hardware-free integration check for the AV formal models.
/// It model-checks every spec and executes representative generated lifecycles.
@main
struct AVPipelineCLI {
    static func main() async throws {
        try CaptureModel.verifySpec(configuration: .standard)
        try WriterModel.verifySpec(configuration: .standard)
        try PlayerModel.verifySpec(configuration: .standard)
        try DiskStoreModel.verifySpec(configuration: .standard)
        try MediaPipelineModel.verifySpec(configuration: .standard)

        let capture = CaptureModel.Machine()
        let pipeline = MediaPipelineModel.Machine()

        _ = try await capture.apply(.configure)
        _ = try await capture.apply(.start)
        _ = try await capture.apply(.stop)
        _ = try await pipeline.apply(.beginCapture)
        _ = try await pipeline.apply(.beginWriting)
        _ = try await pipeline.apply(.finishWriting)
        _ = try await pipeline.apply(.play)
        _ = try await pipeline.apply(.stop)

        print("AV pipeline formal checks passed.")
        print("capture: \(await capture.state.phase.rawValue)")
        print("pipeline: \(await pipeline.state.stage.rawValue)")
    }
}

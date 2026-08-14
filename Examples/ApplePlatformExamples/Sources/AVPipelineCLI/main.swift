import AVPipeline

/// A hardware-free integration check for the AV formal models.
/// It model-checks every spec and executes representative generated lifecycles.
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

        _ = try await capture.execute(CaptureModel.Machine.ActionLabel.configure.toInvocation())
        _ = try await capture.execute(CaptureModel.Machine.ActionLabel.start.toInvocation())
        _ = try await capture.execute(CaptureModel.Machine.ActionLabel.stop.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.beginCapture.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.beginWriting.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.finishWriting.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.play.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.stop.toInvocation())

        print("AV pipeline formal checks passed.")
        print("capture: \(await capture.state.phase.rawValue)")
        print("pipeline: \(await pipeline.state.stage.rawValue)")
    }
}

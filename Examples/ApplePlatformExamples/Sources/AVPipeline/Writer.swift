import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct WriterModel {
    public enum Phase: String, CaseIterable {
        case configured, writing, paused, finished, cancelled
    }
    private enum StartProcess: String, CaseIterable { case startEvent }
    private enum WriteProcess: String, CaseIterable { case writeEvent }
    private enum PauseProcess: String, CaseIterable { case pauseEvent }
    private enum ResumeProcess: String, CaseIterable { case resumeEvent }
    private enum FinishProcess: String, CaseIterable { case finishEvent }
    private enum CancelProcess: String, CaseIterable { case cancelEvent }
    private enum Step: String, CaseIterable { case start, write, pause, resume, finish, cancel }
    public static var spec: TLASpec {
        #spec("WriterModel") {
            Algorithm("WriterModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.configured)
                Each(StartProcess.all) { _ in Do(Step.start) { When(phase == .configured); Assign(phase, to: Phase.writing); Goto(Step.start) } }
                Each(WriteProcess.all) { _ in Do(Step.write) { When(phase == .writing); Assign(phase, to: Phase.writing); Goto(Step.write) } }
                Each(PauseProcess.all) { _ in Do(Step.pause) { When(phase == .writing); Assign(phase, to: Phase.paused); Goto(Step.pause) } }
                Each(ResumeProcess.all) { _ in Do(Step.resume) { When(phase == .paused); Assign(phase, to: Phase.writing); Goto(Step.resume) } }
                Each(FinishProcess.all) { _ in Do(Step.finish) { When(phase == .configured || phase == .writing || phase == .paused); Assign(phase, to: Phase.finished); Goto(Step.finish) } }
                Each(CancelProcess.all) { _ in Do(Step.cancel) { When(phase == .writing || phase == .paused); Assign(phase, to: Phase.cancelled); Goto(Step.cancel) } }
                Invariant("knownWriterPhase") { phase == .configured || phase == .writing || phase == .paused || phase == .finished || phase == .cancelled }
            })
        }
    }
    @TLAActor public actor Machine {}
}

extension Media {
    public actor Writer {
        private let machine = WriterModel.Machine()
        public let writer: AVAssetWriter
        public let input: AVAssetWriterInput
        public init(url: URL, fileType: AVFileType, outputSettings: [String: Any]) throws {
            writer = try AVAssetWriter(url: url, fileType: fileType)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            writer.add(input)
        }
        public func phase() async -> WriterModel.Phase { await machine.state.phase }
        public func start() async throws {
            guard await machine.state.phase == .configured else { throw MediaError.notConfigured }
            writer.startWriting(); writer.startSession(atSourceTime: .zero)
            _ = try await machine.send(.start)
        }
        public func append(_ sample: CMSampleBuffer) async -> Bool {
            guard await machine.state.phase == .writing else { return false }
            _ = try? await machine.send(.write)
            return input.append(sample)
        }
        public func drain(_ stream: AsyncStream<CMSampleBuffer>) async { for await sample in stream { if !(await append(sample)) { break } }; do { try await finish() } catch { await cancel() } }
        public func pause() async { _ = try? await machine.send(.pause) }
        public func resume() async { _ = try? await machine.send(.resume) }
        public func finish() async throws {
            let phase = await machine.state.phase
            guard phase == .configured || phase == .writing || phase == .paused else { throw MediaError.cannotFinish }
            input.markAsFinished(); _ = try await machine.send(.finish)
            await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        }
        public func cancel() async { _ = try? await machine.send(.cancel); writer.cancelWriting() }
    }
}

import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct WriterModel {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case configured, writing, paused, finished, cancelled
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer-phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StartProcess: String, FiniteDomainKey { case startEvent; static let formalDomain: [Self] = [.startEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.start"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum WriteProcess: String, FiniteDomainKey { case writeEvent; static let formalDomain: [Self] = [.writeEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.write"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum PauseProcess: String, FiniteDomainKey { case pauseEvent; static let formalDomain: [Self] = [.pauseEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.pause"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum ResumeProcess: String, FiniteDomainKey { case resumeEvent; static let formalDomain: [Self] = [.resumeEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.resume"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum FinishProcess: String, FiniteDomainKey { case finishEvent; static let formalDomain: [Self] = [.finishEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.finish"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum CancelProcess: String, FiniteDomainKey { case cancelEvent; static let formalDomain: [Self] = [.cancelEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.writer.cancel"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum Step: String, PlusCalLabel { case start, write, pause, resume, finish, cancel }
    public static var spec: TLASpec {
        #spec("WriterModel") {
            Algorithm("WriterModel") {
                let phase = SharedVar(initial: Phase.configured)
                Each(StartProcess.all) { _ in Do(Step.start) { When(phase == .configured); Assign(phase, to: Phase.writing); Goto(Step.start) } }
                Each(WriteProcess.all) { _ in Do(Step.write) { When(phase == .writing); Assign(phase, to: Phase.writing); Goto(Step.write) } }
                Each(PauseProcess.all) { _ in Do(Step.pause) { When(phase == .writing); Assign(phase, to: Phase.paused); Goto(Step.pause) } }
                Each(ResumeProcess.all) { _ in Do(Step.resume) { When(phase == .paused); Assign(phase, to: Phase.writing); Goto(Step.resume) } }
                Each(FinishProcess.all) { _ in Do(Step.finish) { When(phase == .configured || phase == .writing || phase == .paused); Assign(phase, to: Phase.finished); Goto(Step.finish) } }
                Each(CancelProcess.all) { _ in Do(Step.cancel) { When(phase == .writing || phase == .paused); Assign(phase, to: Phase.cancelled); Goto(Step.cancel) } }
                Invariant("knownWriterPhase") { phase == .configured || phase == .writing || phase == .paused || phase == .finished || phase == .cancelled }
            }
        }
    }
    @TLAActor public actor Machine {}
}

extension Media {
    public actor Writer {
        private let machine = WriterModel.Machine()
        public let writer: AVAssetWriter
        public let input: AVAssetWriterInput
        public init(url: URL, fileType: AVFileType, outputSettings: [String: Any]) {
            writer = try! AVAssetWriter(url: url, fileType: fileType)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            writer.add(input)
        }
        public func phase() async -> WriterModel.Phase { await machine.state.phase }
        public func start() async throws {
            guard await machine.state.phase == .configured else { throw MediaError.notConfigured }
            writer.startWriting(); writer.startSession(atSourceTime: .zero)
            _ = try await machine.apply(.start)
        }
        public func append(_ sample: CMSampleBuffer) async -> Bool {
            guard await machine.state.phase == .writing else { return false }
            _ = try? await machine.apply(.write)
            return input.append(sample)
        }
        public func drain(_ stream: AsyncStream<CMSampleBuffer>) async { for await sample in stream { if !(await append(sample)) { break } }; do { try await finish() } catch { await cancel() } }
        public func pause() async { _ = try? await machine.apply(.pause) }
        public func resume() async { _ = try? await machine.apply(.resume) }
        public func finish() async throws {
            let phase = await machine.state.phase
            guard phase == .configured || phase == .writing || phase == .paused else { throw MediaError.cannotFinish }
            input.markAsFinished(); _ = try await machine.apply(.finish)
            await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        }
        public func cancel() async { _ = try? await machine.apply(.cancel); writer.cancelWriting() }
    }
}

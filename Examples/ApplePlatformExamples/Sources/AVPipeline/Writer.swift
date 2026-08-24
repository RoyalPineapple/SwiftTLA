import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct WriterModel {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case configured, writing, paused, finished, cancelled
        public static var defaultValue: Self { .configured }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StartProcess: String, FiniteTLAValueDomain { case startEvent; static var defaultValue: Self { .startEvent }; static let finiteValues: [Self] = [.startEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum WriteProcess: String, FiniteTLAValueDomain { case writeEvent; static var defaultValue: Self { .writeEvent }; static let finiteValues: [Self] = [.writeEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum PauseProcess: String, FiniteTLAValueDomain { case pauseEvent; static var defaultValue: Self { .pauseEvent }; static let finiteValues: [Self] = [.pauseEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum ResumeProcess: String, FiniteTLAValueDomain { case resumeEvent; static var defaultValue: Self { .resumeEvent }; static let finiteValues: [Self] = [.resumeEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum FinishProcess: String, FiniteTLAValueDomain { case finishEvent; static var defaultValue: Self { .finishEvent }; static let finiteValues: [Self] = [.finishEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum CancelProcess: String, FiniteTLAValueDomain { case cancelEvent; static var defaultValue: Self { .cancelEvent }; static let finiteValues: [Self] = [.cancelEvent]; var tlaValue: TLAValue { .string(rawValue) } }
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
}

extension Media {
    public actor Writer {
        private var machine: WriterModel
        public let writer: AVAssetWriter
        public let input: AVAssetWriterInput

        public init(url: URL, fileType: AVFileType, outputSettings: [String: Any]) throws {
            machine = try WriterModel.makeMachine()
            writer = try AVAssetWriter(url: url, fileType: fileType)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            writer.add(input)
        }

        public func phase() async -> WriterModel.Phase { machine.state.phase }

        public func start() async throws {
            guard try machine.isEnabled(.start) else { throw MediaError.notConfigured }
            writer.startWriting(); writer.startSession(atSourceTime: .zero)
            _ = try machine.send(.start)
        }

        public func append(_ sample: CMSampleBuffer) async throws -> Bool {
            _ = try machine.send(.write)
            return input.append(sample)
        }

        public func drain(_ stream: AsyncStream<CMSampleBuffer>) async throws {
            for await sample in stream {
                if try await append(sample) == false { break }
            }
            try await finish()
        }

        public func pause() async throws { _ = try machine.send(.pause) }
        public func resume() async throws { _ = try machine.send(.resume) }

        public func finish() async throws {
            guard try machine.isEnabled(.finish) else { throw MediaError.cannotFinish }
            input.markAsFinished(); _ = try machine.send(.finish)
            await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        }

        public func cancel() async throws {
            _ = try machine.send(.cancel)
            writer.cancelWriting()
        }
    }
}

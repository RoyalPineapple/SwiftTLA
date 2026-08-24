import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct CaptureModel {
    public enum Phase: String, CaseIterable {
        case idle, configured, running, interrupted
    }

    private enum ConfigureProcess: String, CaseIterable { case configureEvent }
    private enum StartProcess: String, CaseIterable { case startEvent }
    private enum StopProcess: String, CaseIterable { case stopEvent }
    private enum InterruptProcess: String, CaseIterable { case interruptEvent }
    private enum ResumeProcess: String, CaseIterable { case resumeEvent }
    private enum Step: String, CaseIterable { case configure, start, stop, interrupt, resume }

    public static var spec: TLASpec {
        #spec("CaptureModel") {
            Algorithm("CaptureModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.idle)
                Each(ConfigureProcess.all) { _ in Do(Step.configure) { When(phase == .idle); Assign(phase, to: Phase.configured); Goto(Step.configure) } }
                Each(StartProcess.all) { _ in Do(Step.start) { When(phase == .configured); Assign(phase, to: Phase.running); Goto(Step.start) } }
                Each(StopProcess.all) { _ in Do(Step.stop) { When(phase == .running || phase == .interrupted); Assign(phase, to: Phase.idle); Goto(Step.stop) } }
                Each(InterruptProcess.all) { _ in Do(Step.interrupt) { When(phase == .running); Assign(phase, to: Phase.interrupted); Goto(Step.interrupt) } }
                Each(ResumeProcess.all) { _ in Do(Step.resume) { When(phase == .interrupted); Assign(phase, to: Phase.running); Goto(Step.resume) } }
                Invariant("knownCapturePhase") { phase == .idle || phase == .configured || phase == .running || phase == .interrupted }
            })
        }
    }

    @TLAActor public actor Machine {}
}

private final class CaptureVideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let continuation: AsyncStream<CMSampleBuffer>.Continuation
    init(continuation: AsyncStream<CMSampleBuffer>.Continuation) { self.continuation = continuation }
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) { continuation.yield(sampleBuffer) }
}

public enum Media {
    private final class CapturePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        weak var actor: Capture?
        func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) { Task { await actor?.didCapture(photo, error) } }
    }

    /// AVFoundation effects are here; the generated machine owns the lifecycle.
    public actor Capture {
        private let machine = CaptureModel.Machine()
        /// AVFoundation owns this reference. The actor owns all lifecycle calls.
        public nonisolated(unsafe) let session = AVCaptureSession()
        private let delegate = CapturePhotoDelegate()
        private let photoOutput = AVCapturePhotoOutput()
        private var photoCont: CheckedContinuation<Data, Error>?

        public init() { delegate.actor = self }
        public func phase() async -> CaptureModel.Phase { await machine.state.phase }

        public func configure(device: AVCaptureDevice) async throws {
            guard await machine.state.phase == .idle else { throw MediaError.cannotConfigure }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.addInput(try AVCaptureDeviceInput(device: device))
            session.addOutput(photoOutput)
            _ = try await machine.send(.configure)
        }

        public func start() async throws {
            guard await machine.state.phase == .configured else { throw MediaError.notConfigured }
            _ = try await machine.send(.start)
            session.startRunning()
        }

        public func stop() async { _ = try? await machine.send(.stop); session.stopRunning() }

        public func capturePhoto() async throws -> Data {
            guard await machine.state.phase == .running else { throw MediaError.notRunning }
            return try await withCheckedThrowingContinuation { continuation in
                photoCont = continuation
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }

        public func stream() async -> AsyncStream<CMSampleBuffer> {
            guard await machine.state.phase == .running else { return AsyncStream { $0.finish() } }
            return AsyncStream { continuation in
                let output = AVCaptureVideoDataOutput()
                output.setSampleBufferDelegate(CaptureVideoDelegate(continuation: continuation), queue: DispatchQueue(label: "video"))
                session.addOutput(output)
            }
        }

        func didCapture(_ photo: AVCapturePhoto?, _ error: Error?) {
            defer { photoCont = nil }
            if let error { photoCont?.resume(throwing: error) }
            else if let data = photo?.fileDataRepresentation() { photoCont?.resume(returning: data) }
            else { photoCont?.resume(throwing: MediaError.noData) }
        }
    }
}

public enum MediaError: Error { case cannotConfigure, notConfigured, notRunning, noData, cannotFinish, alreadyLoaded }

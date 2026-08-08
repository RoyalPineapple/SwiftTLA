import SwiftTLA
import SwiftTLAMacros
import AVFoundation

public enum Media {

    private final class CaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        weak var actor: Capture?
        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            Task { await actor?.didCapture(photo, error) }
        }
    }

    @TLAActor
    public actor Capture {
        public static var spec: TLASpec {
            TLASpec("Capture") {
                let phase = Var<Int>("phase")
                Variable(phase, 0)
                Action("_configure")  { phase == 0 && phase.becomes(1) }
                Action("_start")      { phase == 1 && phase.becomes(2) }
                Action("_stop")       { (phase == 2 || phase == 3) && phase.becomes(0) }
                Action("_interrupt")  { phase == 2 && phase.becomes(3) }
                Action("_resume")     { phase == 3 && phase.becomes(2) }
                Invariant("validPhase") { phase >= 0 && phase <= 3 }
            }
        }

        public let session = AVCaptureSession()
        private let delegate = CaptureDelegate()
        private let photoOutput = AVCapturePhotoOutput()
        private var photoCont: CheckedContinuation<Data, Error>?

        public init() { delegate.actor = self }

        public func configure(device: AVCaptureDevice) throws {
            guard _state.phase == 0 else { throw MediaError.cannotConfigure }
            session.beginConfiguration()
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)
            session.addOutput(photoOutput)
            session.commitConfiguration()
            _configure()
        }

        public func start() async throws {
            guard _state.phase == 1 else { throw MediaError.notConfigured }
            _start()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                session.startRunning()
                c.resume()
            }
        }

        public func stop() { _stop(); session.stopRunning() }

        public func capturePhoto() async throws -> Data {
            guard _state.phase == 2 else { throw MediaError.notRunning }
            return try await withCheckedThrowingContinuation { c in
                self.photoCont = c
                let settings = AVCapturePhotoSettings()
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }

        func didCapture(_ photo: AVCapturePhoto?, _ error: Error?) {
            if let error { photoCont?.resume(throwing: error) }
            else if let data = photo?.fileDataRepresentation() { photoCont?.resume(returning: data) }
            else { photoCont?.resume(throwing: MediaError.noData) }
            photoCont = nil
        }
    }
}

public enum MediaError: Error { case cannotConfigure, notConfigured, notRunning, noData, cannotFinish, alreadyLoaded }

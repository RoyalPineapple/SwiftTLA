import AVFoundation

private final class CameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var capture: CameraCapture?

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { await capture?.didCapture(photo, error) }
    }
}

/// AVFoundation session ownership for a `CameraWorkflow` effect boundary.
public actor CameraCapture {
    public nonisolated(unsafe) let session = AVCaptureSession()
    private let photoDelegate = CameraPhotoDelegate()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    public init() {
        photoDelegate.capture = self
    }

    public func configureAndStart(
        device: AVCaptureDevice,
        recordingOutput: AVCaptureMovieFileOutput
    ) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.addInput(try AVCaptureDeviceInput(device: device))
        session.addOutput(photoOutput)
        session.addOutput(recordingOutput)
        session.startRunning()
    }

    public func capturePhoto() async throws -> Data {
        guard session.isRunning else { throw CameraCaptureError.notRunning }
        return try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: photoDelegate)
        }
    }

    func didCapture(_ photo: AVCapturePhoto?, _ error: Error?) {
        defer { photoContinuation = nil }
        if let error {
            photoContinuation?.resume(throwing: error)
        } else if let data = photo?.fileDataRepresentation() {
            photoContinuation?.resume(returning: data)
        } else {
            photoContinuation?.resume(throwing: CameraCaptureError.noData)
        }
    }
}

public enum CameraCaptureError: Error {
    case notRunning
    case noData
}

import Foundation

public struct RecordingCallbackCorrelation: Sendable {
    private struct Attempt: Sendable {
        let id: UUID
        var cancellationRequested = false
    }

    private var pendingAttempt: Attempt?

    public var pendingAttemptID: UUID? { pendingAttempt?.id }

    public init() {}

    public mutating func begin(id: UUID = UUID()) -> UUID? {
        guard pendingAttempt == nil else { return nil }
        pendingAttempt = Attempt(id: id)
        return id
    }

    public mutating func discard(attemptID: UUID) {
        guard pendingAttemptID == attemptID else { return }
        pendingAttempt = nil
    }

    @discardableResult
    public mutating func requestCancellation(for attemptID: UUID) -> Bool {
        guard var pendingAttempt, pendingAttempt.id == attemptID else { return false }
        pendingAttempt.cancellationRequested = true
        self.pendingAttempt = pendingAttempt
        return true
    }

    public mutating func consumeCallback(for attemptID: UUID, error: Error?) -> CameraWorkflow.Action? {
        guard let pendingAttempt, pendingAttempt.id == attemptID else { return nil }
        self.pendingAttempt = nil
        if pendingAttempt.cancellationRequested {
            return .recordingCancelled
        }
        return error == nil ? .recordingSucceeded : .recordingFailed
    }
}

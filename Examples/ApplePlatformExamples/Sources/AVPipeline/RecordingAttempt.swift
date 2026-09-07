import Foundation

public struct RecordingAttempt: Sendable, Equatable {
    public let id: UUID
    private var cancellationRequested = false
    private var outcomeSubmitted = false

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public mutating func requestCancellation() {
        cancellationRequested = true
    }

    public mutating func consumeCallback(error: Error?, wasCancelled: Bool) -> CameraWorkflow.Action? {
        guard !outcomeSubmitted else { return nil }
        outcomeSubmitted = true

        if cancellationRequested || wasCancelled {
            return .recordingCancelled
        }
        return error == nil ? .recordingSucceeded : .recordingFailed
    }
}

public enum RecordingCallbackDisposition: Sendable, Equatable {
    case submitted(attemptID: UUID, action: CameraWorkflow.Action)
    case ignored(callbackID: UUID, activeAttemptID: UUID?)
}

public struct RecordingCallbackCorrelation: Sendable {
    public private(set) var pendingAttemptID: UUID?
    private var pendingAttempt: RecordingAttempt?

    public init() {}

    public mutating func begin(_ attempt: RecordingAttempt) {
        precondition(pendingAttempt == nil, "A recording callback is already pending.")
        pendingAttempt = attempt
        pendingAttemptID = attempt.id
    }

    public mutating func discard(attemptID: UUID) {
        guard pendingAttemptID == attemptID else { return }
        pendingAttempt = nil
        pendingAttemptID = nil
    }

    @discardableResult
    public mutating func requestCancellation(for attemptID: UUID) -> Bool {
        guard var pendingAttempt, pendingAttempt.id == attemptID else { return false }
        pendingAttempt.requestCancellation()
        self.pendingAttempt = pendingAttempt
        return true
    }

    public mutating func consumeCallback(
        for attemptID: UUID,
        error: Error?,
        wasCancelled: Bool
    ) -> RecordingCallbackDisposition {
        guard var pendingAttempt, pendingAttempt.id == attemptID else {
            return .ignored(callbackID: attemptID, activeAttemptID: pendingAttemptID)
        }
        guard let action = pendingAttempt.consumeCallback(error: error, wasCancelled: wasCancelled) else {
            return .ignored(callbackID: attemptID, activeAttemptID: pendingAttemptID)
        }
        self.pendingAttempt = nil
        pendingAttemptID = nil
        return .submitted(attemptID: attemptID, action: action)
    }
}

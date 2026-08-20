import Foundation

/// Why a state-bearing observation was sent.
public enum TLALiveMachineSnapshotReason: Sendable, Equatable {
    /// The atomic baseline captured while attaching to an existing runtime.
    case attached
    /// The atomic baseline that re-establishes continuity after delivery loss.
    case resynchronized(after: TLALiveMachineObservationLoss)
}

/// The explicit boundary where an observer can no longer treat delivery as contiguous.
public struct TLALiveMachineObservationLoss: Sendable, Equatable {
    public let identity: TLALiveMachineIdentity
    public let lastContiguousPosition: TLALiveMachinePosition
    public let latestKnownPosition: TLALiveMachinePosition

    public init(
        identity: TLALiveMachineIdentity,
        lastContiguousPosition: TLALiveMachinePosition,
        latestKnownPosition: TLALiveMachinePosition
    ) {
        self.identity = identity
        self.lastContiguousPosition = lastContiguousPosition
        self.latestKnownPosition = latestKnownPosition
    }
}

/// The owner-ended terminal event for one observation subscription.
public struct TLALiveMachineTermination: Sendable, Equatable {
    public let identity: TLALiveMachineIdentity
    public let finalPosition: TLALiveMachinePosition
    public let reason: TLALiveMachineUnavailableReason

    public init(
        identity: TLALiveMachineIdentity,
        finalPosition: TLALiveMachinePosition,
        reason: TLALiveMachineUnavailableReason
    ) {
        self.identity = identity
        self.finalPosition = finalPosition
        self.reason = reason
    }
}

/// One event from an attached live-machine observation.
public enum TLALiveMachineObservationEvent<Action: Sendable & Equatable>: Sendable, Equatable {
    /// An atomic baseline captured at attachment or recovery.
    case snapshot(TLALiveMachineSnapshot, reason: TLALiveMachineSnapshotReason)
    /// One committed transition in this runtime's commit order.
    case update(TLALiveMachineCommit<Action>)
    /// A bounded mailbox discarded one or more ordinary updates.
    case loss(TLALiveMachineObservationLoss)
    /// The owner ended the runtime. This is delivered at most once.
    case terminated(TLALiveMachineTermination)
}

/// The result of attaching an observer to an existing runtime.
public enum TLALiveMachineAttachmentOutcome<Action: Sendable & Equatable>: Sendable {
    case attached(TLALiveMachineObservationSubscription<Action>)
    case unavailable(TLALiveMachineUnavailableReason)
}

/// The result of asking a subscription to establish a fresh atomic baseline.
public enum TLALiveMachineResynchronizationOutcome: Sendable, Equatable {
    /// A resynchronization snapshot is queued at this position.
    case resumed(at: TLALiveMachinePosition)
    /// The runtime ended before a fresh snapshot could be captured.
    case terminated(TLALiveMachineTermination)
    /// The subscription was cancelled before recovery could occur.
    case cancelled
}

/// A non-owning, single-consumer observation of one live runtime.
///
/// The subscription carries no machine state. Its operations route to the
/// authoritative runtime storage actor, where attachment, commits, recovery,
/// cancellation, and owner termination are serialized.
public final class TLALiveMachineObservationSubscription<Action: Sendable & Equatable>: AsyncSequence, Sendable {
    public typealias Element = TLALiveMachineObservationEvent<Action>

    public let identity: TLALiveMachineIdentity
    private let subscriptionID: UUID
    private let storage: TLALiveMachineStorage<Action>

    init(identity: TLALiveMachineIdentity, subscriptionID: UUID, storage: TLALiveMachineStorage<Action>) {
        self.identity = identity
        self.subscriptionID = subscriptionID
        self.storage = storage
    }

    deinit {
        let storage = storage
        let subscriptionID = subscriptionID
        Task { await storage.cancel(subscriptionID) }
    }

    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        private let subscription: TLALiveMachineObservationSubscription<Action>

        init(subscription: TLALiveMachineObservationSubscription<Action>) {
            self.subscription = subscription
        }

        public mutating func next() async -> TLALiveMachineObservationEvent<Action>? {
            let observation = subscription
            return await withTaskCancellationHandler {
                await observation.next()
            } onCancel: {
                Task { await observation.cancel() }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(subscription: self)
    }

    /// Queues an atomic recovery snapshot after an explicit loss boundary.
    public func resynchronize() async -> TLALiveMachineResynchronizationOutcome {
        await storage.resynchronize(subscriptionID)
    }

    /// Idempotently ends only this subscription.
    public func cancel() async {
        await storage.cancel(subscriptionID)
    }

    private func next() async -> TLALiveMachineObservationEvent<Action>? {
        await storage.next(subscriptionID)
    }
}

import Foundation
import os

/// Identifies one live runtime for its entire lifetime.
///
/// Every handle, snapshot, and outcome produced by one runtime carries the
/// same identity; separately created runtimes are always distinct. The value
/// is a wrapped UUID so application code cannot accidentally treat unrelated
/// identifiers as interchangeable.
public struct TLALiveMachineIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: UUID

    public init(value: UUID = UUID()) {
        self.value = value
    }

    public var description: String { value.uuidString }
}

/// The commit-ordering point of one live runtime.
///
/// Positions start at zero and advance exactly once per committed action.
/// They are per-runtime and imply no cross-runtime order. Advancing is total
/// while the value is below `UInt64.max`; position exhaustion fails a request
/// before commit instead of wrapping.
public struct TLALiveMachinePosition: Comparable, Codable, Sendable, CustomStringConvertible {
    public let value: UInt64

    public init(value: UInt64) {
        self.value = value
    }

    /// The position one commit later, or `nil` when the ordering space is
    /// exhausted.
    public var next: TLALiveMachinePosition? {
        guard value < UInt64.max else { return nil }
        return .init(value: value + 1)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String { String(value) }
}

/// One complete committed observation of a live runtime.
///
/// The snapshot binds the runtime identity, ordering position, and the validated state projection that was current at that
/// position. Consumers read one complete committed state; they never see a
/// mixture of fields from different states or a raw formal-state map.
public struct TLALiveMachineSnapshot: Sendable, Equatable {
    public let identity: TLALiveMachineIdentity
    public let position: TLALiveMachinePosition
    public let state: TLAStateProjection

    public init(
        identity: TLALiveMachineIdentity,
        position: TLALiveMachinePosition,
        state: TLAStateProjection
    ) {
        self.identity = identity
        self.position = position
        self.state = state
    }
}

/// The result of requesting the current snapshot of a live runtime.
public enum TLALiveMachineCurrentResult: Sendable, Equatable {
    /// A complete committed snapshot of the active runtime.
    case snapshot(TLALiveMachineSnapshot)
    /// The runtime can no longer serve snapshots.
    case unavailable(TLALiveMachineUnavailableReason)
}

/// Why a live runtime can no longer serve snapshots or accept requests.
///
/// Later observation and adapter phases reuse this type for terminal
/// delivery instead of introducing a second lifecycle state.
public enum TLALiveMachineUnavailableReason: Sendable, Equatable, CustomStringConvertible {
    /// The declared owner ended the runtime.
    case endedByOwner

    public var code: String {
        switch self {
        case .endedByOwner: return "endedByOwner"
        }
    }

    public var description: String {
        switch self {
        case .endedByOwner:
            return "The runtime was ended by its owner."
        }
    }
}

/// A request the runtime rejected before accepting execution.
///
/// Rejection is a pre-acceptance outcome: the requested transition is never
/// evaluated on these paths and no state or position changes. The retained
/// snapshot lets a caller prove that position and state did not move.
public struct TLALiveActionRejection<Action: Sendable & Equatable>: Sendable, Equatable {
    public enum Reason: Sendable, Equatable, CustomStringConvertible {
        case runtimeUnavailable(TLALiveMachineUnavailableReason)
        case actionNotEnabled
        case identityRoutedActionRequiresID

        public var code: String {
            switch self {
            case .runtimeUnavailable(let reason): return "runtimeUnavailable.\(reason.code)"
            case .actionNotEnabled: return "actionNotEnabled"
            case .identityRoutedActionRequiresID: return "identityRoutedActionRequiresID"
            }
        }

        public var description: String {
            switch self {
            case .runtimeUnavailable(let reason):
                return "The runtime cannot execute the request: \(reason)"
            case .actionNotEnabled:
                return "The requested action is not enabled in the current state."
            case .identityRoutedActionRequiresID:
                return "The requested action selects an identified collection member and must be routed through the model's identified action surface."
            }
        }
    }

    public let requestID: UUID
    public let action: Action
    public let reason: Reason
    public let current: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        action: Action,
        reason: Reason,
        current: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.action = action
        self.reason = reason
        self.current = current
    }
}

/// An accepted request whose execution completed without committing.
///
/// A failure is the ordinary noncommit outcome of accepted execution: the
/// runtime attempted the transition and could not complete it, and the
/// retained snapshot proves the runtime's state and position are unchanged.
public struct TLALiveActionFailure<Action: Sendable & Equatable>: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case evaluationFailed
        case decodeFailed
        case positionExhausted
        /// The typed action produced more than one successor state.
        case ambiguousSuccessors
    }

    public let requestID: UUID
    public let action: Action
    public let code: Code
    public let message: String
    public let current: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        action: Action,
        code: Code,
        message: String,
        current: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.action = action
        self.code = code
        self.message = message
        self.current = current
    }
}

/// The evidence of one committed live transition.
///
/// A commit is the only outcome that means mutation occurred. The runtime
/// replaced its state and advanced its position atomically, so
/// `after.position` is exactly one past `before.position`.
public struct TLALiveMachineCommit<Action: Sendable & Equatable>: Sendable, Equatable {
    public let requestID: UUID
    public let action: Action
    public let before: TLALiveMachineSnapshot
    public let after: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        action: Action,
        before: TLALiveMachineSnapshot,
        after: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.action = action
        self.before = before
        self.after = after
    }
}

/// The exhaustive result of one live action request.
///
/// An accepted request completes as exactly one committed transition or one
/// normal failure; caller cancellation cannot produce or relabel either
/// outcome. Rejection is a pre-acceptance lifecycle or validation outcome.
public enum TLALiveActionOutcome<Action: Sendable & Equatable>: Sendable, Equatable {
    case committed(TLALiveMachineCommit<Action>)
    case rejected(TLALiveActionRejection<Action>)
    case failed(TLALiveActionFailure<Action>)
}

/// The typed transition behavior of a live runtime.
public struct TLALiveMachineTransitionDriver<Action: Sendable & Equatable>: Sendable {
    public let successors: @Sendable (TLAStateProjection, Action) throws -> [TLAStateProjection]
    public let validateAction: @Sendable (Action) -> TLALiveActionRejection<Action>.Reason?
    public let decodeState: @Sendable (TLAStateProjection) throws -> Void

    public init(
        successors: @escaping @Sendable (TLAStateProjection, Action) throws -> [TLAStateProjection],
        validateAction: @escaping @Sendable (Action) -> TLALiveActionRejection<Action>.Reason?,
        decodeState: @escaping @Sendable (TLAStateProjection) throws -> Void
    ) {
        self.successors = successors
        self.validateAction = validateAction
        self.decodeState = decodeState
    }
}

/// An immutable handle to the one authoritative live runtime.
///
/// Handle copies share the same storage actor and stable identity, so a
/// commit made through one handle is immediately visible through every other
/// handle of the same runtime. A handle exposes identity, schema, current
/// snapshots, and typed action execution.
public struct TLALiveMachine<Action: Sendable & Equatable>: Sendable {
    public let identity: TLALiveMachineIdentity
    public let schema: MachineSchema
    private let storage: TLALiveMachineStorage<Action>

    init(identity: TLALiveMachineIdentity, schema: MachineSchema, storage: TLALiveMachineStorage<Action>) {
        self.identity = identity
        self.schema = schema
        self.storage = storage
    }

    /// The current committed snapshot, or the reason none is available.
    public func current() async -> TLALiveMachineCurrentResult {
        await storage.current()
    }

    /// Attaches a non-owning observer to this existing runtime.
    ///
    /// Attachment captures its initial snapshot and registers delivery in one
    /// storage-actor operation, so an overlapping commit is either part of the
    /// baseline or appears once as the following update.
    public func observe() async -> TLALiveMachineAttachmentOutcome<Action> {
        await storage.observe()
    }

    public func execute(_ action: Action, requestID: UUID = UUID()) async -> TLALiveActionOutcome<Action> {
        await storage.execute(action, requestID: requestID)
    }
}

/// The declared owner of one live runtime.
///
/// Creation returns the owner, which vends the common handle and holds the
/// only explicit shutdown authority. Ending is idempotent and explicit;
/// releasing non-owner handles never ends an otherwise live runtime.
public final class TLALiveMachineOwner<Action: Sendable & Equatable>: Sendable {
    private let storage: TLALiveMachineStorage<Action>
    public let identity: TLALiveMachineIdentity
    public let schema: MachineSchema

    private init(storage: TLALiveMachineStorage<Action>, identity: TLALiveMachineIdentity, schema: MachineSchema) {
        self.storage = storage
        self.identity = identity
        self.schema = schema
    }

    /// Creates a new runtime with a fresh identity, an initial committed
    /// state, and the supplied formal transition driver.
    public static func create(
        schema: MachineSchema,
        initial: TLAStateProjection,
        driver: TLALiveMachineTransitionDriver<Action>
    ) -> TLALiveMachineOwner<Action> {
        let identity = TLALiveMachineIdentity()
        let storage = TLALiveMachineStorage(identity: identity, schema: schema, initial: initial, driver: driver)
        return TLALiveMachineOwner(storage: storage, identity: identity, schema: schema)
    }

    /// Creates a runtime with a focused-test observation mailbox capacity.
    ///
    /// Production callers use ``create(schema:initial:driver:)`` and receive
    /// the fixed delivery policy. This internal seam exists only to make loss
    /// behavior deterministic in the package's contract tests.
    static func create(
        schema: MachineSchema,
        initial: TLAStateProjection,
        driver: TLALiveMachineTransitionDriver<Action>,
        observationMailboxCapacity: Int
    ) -> TLALiveMachineOwner<Action> {
        let identity = TLALiveMachineIdentity()
        let storage = TLALiveMachineStorage(
            identity: identity,
            schema: schema,
            initial: initial,
            driver: driver,
            observationMailboxCapacity: observationMailboxCapacity
        )
        return TLALiveMachineOwner(storage: storage, identity: identity, schema: schema)
    }

    /// The common handle for this runtime.
    public var handle: TLALiveMachine<Action> {
        TLALiveMachine(identity: identity, schema: schema, storage: storage)
    }

    /// Ends this runtime. Idempotent; after ending, snapshots report
    /// unavailability and requests are rejected for this identity.
    public func end() async {
        await storage.end()
    }
}

/// The sole mutable live-machine storage for one runtime identity.
///
/// Every public surface reads or mutates this actor; no supported operation
/// creates a competing live copy. The commit section is non-suspending, so
/// once a request is accepted it resolves as exactly one commit or failure.
actor TLALiveMachineStorage<Action: Sendable & Equatable> {
    let identity: TLALiveMachineIdentity
    let schema: MachineSchema
    let driver: TLALiveMachineTransitionDriver<Action>
    var state: TLAStateProjection
    var position = TLALiveMachinePosition(value: 0)
    private var isEnded = false
    private let observationMailboxCapacity: Int
    private var subscriptions: [UUID: ObservationSubscriptionState<Action>] = [:]
    private let logger = Logger(subsystem: "SwiftTLA", category: "LiveMachine")

    init(
        identity: TLALiveMachineIdentity,
        schema: MachineSchema,
        initial: TLAStateProjection,
        driver: TLALiveMachineTransitionDriver<Action>,
        observationMailboxCapacity: Int = 64
    ) {
        self.identity = identity
        self.schema = schema
        self.state = initial
        self.driver = driver
        self.observationMailboxCapacity = max(1, observationMailboxCapacity)
    }

    func current() -> TLALiveMachineCurrentResult {
        if isEnded { return .unavailable(.endedByOwner) }
        return .snapshot(makeSnapshot())
    }

    func observe() -> TLALiveMachineAttachmentOutcome<Action> {
        guard !isEnded else { return .unavailable(.endedByOwner) }
        let subscriptionID = UUID()
        let snapshot = makeSnapshot()
        subscriptions[subscriptionID] = .init(
            events: [.snapshot(snapshot, reason: .attached)],
            continuityAnchor: snapshot.position
        )
        return .attached(.init(identity: identity, subscriptionID: subscriptionID, storage: self))
    }

    func next(_ subscriptionID: UUID) async -> TLALiveMachineObservationEvent<Action>? {
        guard var subscription = subscriptions[subscriptionID] else { return nil }
        if !subscription.events.isEmpty {
            let event = subscription.events.removeFirst()
            subscription.didDeliver(event)
            if subscription.isClosed && subscription.events.isEmpty {
                subscriptions.removeValue(forKey: subscriptionID)
            } else {
                subscriptions[subscriptionID] = subscription
            }
            return event
        }
        guard !subscription.isClosed else {
            subscriptions.removeValue(forKey: subscriptionID)
            return nil
        }
        return await withCheckedContinuation { continuation in
            subscription.waiter = continuation
            subscriptions[subscriptionID] = subscription
        }
    }

    func resynchronize(_ subscriptionID: UUID) -> TLALiveMachineResynchronizationOutcome {
        guard var subscription = subscriptions[subscriptionID] else { return .cancelled }
        guard !isEnded else {
            return .terminated(.init(identity: identity, finalPosition: position, reason: .endedByOwner))
        }
        guard subscription.isLossPending else {
            return .resumed(at: position)
        }
        guard let loss = subscription.loss else { return .cancelled }
        let snapshot = makeSnapshot()
        subscription.events.removeAll { event in
            if case .update = event { return true }
            if case .loss = event { return true }
            return false
        }
        subscription.ordinaryUpdateCount = 0
        subscription.isLossPending = false
        subscription.loss = nil
        subscription.enqueueControl(.snapshot(snapshot, reason: .resynchronized(after: loss)))
        subscription.resumeWaiterIfPossible()
        subscriptions[subscriptionID] = subscription
        return .resumed(at: snapshot.position)
    }

    func cancel(_ subscriptionID: UUID) {
        guard let subscription = subscriptions[subscriptionID] else { return }
        // Owner shutdown won the race: preserve its already-queued terminal.
        guard !subscription.isClosed else { return }
        subscriptions.removeValue(forKey: subscriptionID)
        subscription.waiter?.resume(returning: nil)
    }

    func end() {
        guard !isEnded else { return }
        isEnded = true
        let termination = TLALiveMachineTermination(
            identity: identity,
            finalPosition: position,
            reason: .endedByOwner
        )
        for subscriptionID in Array(subscriptions.keys) {
            guard var subscription = subscriptions[subscriptionID], !subscription.isClosed else { continue }
            subscription.enqueueControl(.terminated(termination))
            subscription.isClosed = true
            subscription.resumeWaiterIfPossible()
            subscriptions[subscriptionID] = subscription
        }
        log("ended")
    }

    func execute(_ action: Action, requestID: UUID) -> TLALiveActionOutcome<Action> {
        guard !isEnded else {
            return rejected(.runtimeUnavailable(.endedByOwner), action: action, requestID: requestID, current: makeSnapshot())
        }
        let before = makeSnapshot()
        if let reason = driver.validateAction(action) {
            return rejected(reason, action: action, requestID: requestID, current: before)
        }
        let candidates: [TLAStateProjection]
        do {
            candidates = try driver.successors(state, action)
        } catch {
            return failed(
                code: .evaluationFailed,
                message: String(describing: error),
                action: action,
                requestID: requestID,
                current: before
            )
        }
        // Live execution requires one deterministic successor: model
        // nondeterminism must be resolved by the caller (parameterized
        // actions or explicit successor selection) before the request is
        // constructed. Never let successor array order pick the committed
        // state.
        if candidates.count > 1 {
            return failed(
                code: .ambiguousSuccessors,
                message: "The action produced \(candidates.count) successor states; live execution requires a deterministic successor.",
                action: action,
                requestID: requestID,
                current: before
            )
        }
        guard let candidate = candidates.first else {
            return rejected(.actionNotEnabled, action: action, requestID: requestID, current: before)
        }
        do {
            try driver.decodeState(candidate)
        } catch {
            return failed(
                code: .decodeFailed,
                message: String(describing: error),
                action: action,
                requestID: requestID,
                current: before
            )
        }
        guard let nextPosition = position.next else {
            return failed(
                code: .positionExhausted,
                message: "The runtime ordering position is exhausted.",
                action: action,
                requestID: requestID,
                current: before
            )
        }
        state = candidate
        position = nextPosition
        let after = makeSnapshot()
        let commit = TLALiveMachineCommit(
            requestID: requestID,
            action: action,
            before: before,
            after: after
        )
        publish(commit)
        log("committed", requestID: requestID)
        return .committed(commit)
    }

    private func publish(_ commit: TLALiveMachineCommit<Action>) {
        for subscriptionID in Array(subscriptions.keys) {
            guard var subscription = subscriptions[subscriptionID], !subscription.isClosed else { continue }
            subscription.enqueueUpdate(
                commit,
                capacity: observationMailboxCapacity,
                identity: identity
            )
            subscription.resumeWaiterIfPossible()
            subscriptions[subscriptionID] = subscription
        }
    }

    private func makeSnapshot() -> TLALiveMachineSnapshot {
        return .init(
            identity: identity,
            position: position,
            state: state
        )
    }

    private func rejected(
        _ reason: TLALiveActionRejection<Action>.Reason,
        action: Action,
        requestID: UUID,
        current: TLALiveMachineSnapshot
    ) -> TLALiveActionOutcome<Action> {
        log("rejected", requestID: requestID, detail: "reason=\(reason.code)")
        return .rejected(.init(
            requestID: requestID,
            action: action,
            reason: reason,
            current: current
        ))
    }

    private func failed(
        code: TLALiveActionFailure<Action>.Code,
        message: String,
        action: Action,
        requestID: UUID,
        current: TLALiveMachineSnapshot
    ) -> TLALiveActionOutcome<Action> {
        log("failed", requestID: requestID, detail: "code=\(code.rawValue)")
        return .failed(.init(
            requestID: requestID,
            action: action,
            code: code,
            message: message,
            current: current
        ))
    }

    private func log(_ outcome: String, requestID: UUID? = nil, detail: String = "") {
        let identityValue = identity.value.uuidString
        let requestID = requestID?.uuidString ?? "-"
        let positionValue = position.value
        logger.notice("outcome=\(outcome, privacy: .public) identity=\(identityValue, privacy: .public) request=\(requestID, privacy: .public) position=\(positionValue, privacy: .public) detail=\(detail, privacy: .public)")
    }
}

private struct ObservationSubscriptionState<Action: Sendable & Equatable> {
    var events: [TLALiveMachineObservationEvent<Action>]
    var ordinaryUpdateCount = 0
    var continuityAnchor: TLALiveMachinePosition
    var isLossPending = false
    var loss: TLALiveMachineObservationLoss?
    var isClosed = false
    var waiter: CheckedContinuation<TLALiveMachineObservationEvent<Action>?, Never>?

    init(events: [TLALiveMachineObservationEvent<Action>], continuityAnchor: TLALiveMachinePosition) {
        self.events = events
        self.continuityAnchor = continuityAnchor
    }

    mutating func enqueueUpdate(
        _ commit: TLALiveMachineCommit<Action>,
        capacity: Int,
        identity: TLALiveMachineIdentity
    ) {
        guard !isLossPending else { return }
        guard ordinaryUpdateCount < capacity else {
            events.removeAll { event in
                if case .update = event { return true }
                return false
            }
            ordinaryUpdateCount = 0
            let loss = TLALiveMachineObservationLoss(
                identity: identity,
                lastContiguousPosition: continuityAnchor,
                latestKnownPosition: commit.after.position
            )
            self.loss = loss
            isLossPending = true
            enqueueControl(.loss(loss))
            return
        }
        events.append(.update(commit))
        ordinaryUpdateCount += 1
    }

    mutating func enqueueControl(_ event: TLALiveMachineObservationEvent<Action>) {
        events.append(event)
    }

    mutating func didDeliver(_ event: TLALiveMachineObservationEvent<Action>) {
        switch event {
        case .snapshot(let snapshot, _):
            continuityAnchor = snapshot.position
        case .update(let commit):
            ordinaryUpdateCount -= 1
            continuityAnchor = commit.after.position
        case .loss, .terminated:
            break
        }
    }

    mutating func resumeWaiterIfPossible() {
        guard let waiter, !events.isEmpty else { return }
        let event = events.removeFirst()
        self.waiter = nil
        didDeliver(event)
        waiter.resume(returning: event)
    }
}

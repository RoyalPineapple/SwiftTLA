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
/// The snapshot binds the runtime identity, schema identifier, ordering
/// position, and the validated state projection that was current at that
/// position. Consumers read one complete committed state; they never see a
/// mixture of fields from different states or a raw formal-state map.
public struct TLALiveMachineSnapshot: Sendable, Equatable {
    public let identity: TLALiveMachineIdentity
    public let schemaIdentifier: String
    public let position: TLALiveMachinePosition
    public let state: TLAStateProjection
    public let availability: TLAMachineObservation.Availability

    public init(
        identity: TLALiveMachineIdentity,
        schemaIdentifier: String,
        position: TLALiveMachinePosition,
        state: TLAStateProjection,
        availability: TLAMachineObservation.Availability
    ) {
        self.identity = identity
        self.schemaIdentifier = schemaIdentifier
        self.position = position
        self.state = state
        self.availability = availability
    }

    /// The same observation in the generated-machine observation shape.
    public var observation: TLAMachineObservation {
        .init(state: state, availability: availability)
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

/// An action request addressed to one live runtime.
///
/// The request carries a correlation identifier, the target runtime identity,
/// and the schema identifier the caller believes the runtime exposes. The
/// runtime revalidates all three before accepting execution.
public struct TLALiveActionRequest: Sendable, Equatable {
    public let requestID: UUID
    public let target: TLALiveMachineIdentity
    public let schemaIdentifier: String
    public let invocation: TLAActionInvocation

    public init(
        requestID: UUID,
        target: TLALiveMachineIdentity,
        schemaIdentifier: String,
        invocation: TLAActionInvocation
    ) {
        self.requestID = requestID
        self.target = target
        self.schemaIdentifier = schemaIdentifier
        self.invocation = invocation
    }
}

/// A request the runtime rejected before accepting execution.
///
/// Rejection is a pre-acceptance outcome: the requested transition is never
/// evaluated on these paths and no state or position changes. The retained
/// snapshot lets a caller prove that position and state did not move.
public struct TLALiveActionRejection: Sendable, Equatable {
    public enum Reason: Sendable, Equatable, CustomStringConvertible {
        case runtimeUnavailable(TLALiveMachineUnavailableReason)
        case identityMismatch
        case schemaMismatch
        case unknownAction
        case invalidArity
        case actionArgumentOutOfDomain
        case actionNotEnabled
        case identityRoutedActionRequiresID

        public var code: String {
            switch self {
            case .runtimeUnavailable(let reason): return "runtimeUnavailable.\(reason.code)"
            case .identityMismatch: return "identityMismatch"
            case .schemaMismatch: return "schemaMismatch"
            case .unknownAction: return "unknownAction"
            case .invalidArity: return "invalidArity"
            case .actionArgumentOutOfDomain: return "actionArgumentOutOfDomain"
            case .actionNotEnabled: return "actionNotEnabled"
            case .identityRoutedActionRequiresID: return "identityRoutedActionRequiresID"
            }
        }

        public var description: String {
            switch self {
            case .runtimeUnavailable(let reason):
                return "The runtime cannot execute the request: \(reason)"
            case .identityMismatch:
                return "The request targets a different runtime identity."
            case .schemaMismatch:
                return "The request declares a schema identifier that does not match this runtime."
            case .unknownAction:
                return "The requested action is not declared by this runtime's schema."
            case .invalidArity:
                return "The requested action's argument count does not match its declared parameters."
            case .actionArgumentOutOfDomain:
                return "The requested action has arguments outside its declared finite domains."
            case .actionNotEnabled:
                return "The requested action is not enabled in the current state."
            case .identityRoutedActionRequiresID:
                return "The requested action selects an identified collection member and must be routed through the model's identified action surface."
            }
        }
    }

    public let requestID: UUID
    public let invocation: TLAActionInvocation
    public let reason: Reason
    public let current: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        invocation: TLAActionInvocation,
        reason: Reason,
        current: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.invocation = invocation
        self.reason = reason
        self.current = current
    }
}

/// An accepted request whose execution completed without committing.
///
/// A failure is the ordinary noncommit outcome of accepted execution: the
/// runtime attempted the transition and could not complete it, and the
/// retained snapshot proves the runtime's state and position are unchanged.
public struct TLALiveActionFailure: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case evaluationFailed
        case decodeFailed
        case positionExhausted
        /// The accepted action produced more than one formal successor state.
        ///
        /// Live execution requires a deterministic successor, so the runtime
        /// never lets successor array order choose the committed state.
        /// Model nondeterminism must be resolved by the caller before the
        /// request is constructed — via parameterized actions or explicit
        /// successor selection. The failure leaves state and position
        /// unchanged.
        case ambiguousSuccessors
    }

    public let requestID: UUID
    public let invocation: TLAActionInvocation
    public let code: Code
    public let message: String
    public let current: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        invocation: TLAActionInvocation,
        code: Code,
        message: String,
        current: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.invocation = invocation
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
public struct TLALiveMachineCommit: Sendable, Equatable {
    public let requestID: UUID
    public let invocation: TLAActionInvocation
    public let before: TLALiveMachineSnapshot
    public let after: TLALiveMachineSnapshot

    public init(
        requestID: UUID,
        invocation: TLAActionInvocation,
        before: TLALiveMachineSnapshot,
        after: TLALiveMachineSnapshot
    ) {
        self.requestID = requestID
        self.invocation = invocation
        self.before = before
        self.after = after
    }
}

/// The exhaustive result of one live action request.
///
/// An accepted request completes as exactly one committed transition or one
/// normal failure; caller cancellation cannot produce or relabel either
/// outcome. Rejection is a pre-acceptance lifecycle or validation outcome.
public enum TLALiveActionOutcome: Sendable, Equatable {
    case committed(TLALiveMachineCommit)
    case rejected(TLALiveActionRejection)
    case failed(TLALiveActionFailure)
}

/// The formal transition behavior a live runtime executes.
///
/// The driver is the only bridge between the runtime and the formal engine.
/// It supplies successor computation, availability enumeration, finite-domain
/// request validation, and typed state decoding. Generated machines build one
/// driver from a single compiled model so the live runtime never duplicates
/// model state or formal semantics.
public struct TLALiveMachineTransitionDriver: Sendable {
    public let successors: @Sendable (TLAStateProjection, TLAActionInvocation) throws -> [TLAStateProjection]
    public let availableInvocations: @Sendable (TLAStateProjection) throws -> [TLAActionInvocation]
    /// Returns a rejection reason for a structurally unknown, out-of-domain,
    /// or identity-routed invocation, or `nil` when the invocation is valid
    /// for the model.
    public let validateInvocation: @Sendable (TLAActionInvocation) -> TLALiveActionRejection.Reason?
    /// Validates that a formal successor decodes into the model's generated
    /// typed state. Throwing discards the successor before any commit.
    public let decodeState: @Sendable (TLAStateProjection) throws -> Void

    public init(
        successors: @escaping @Sendable (TLAStateProjection, TLAActionInvocation) throws -> [TLAStateProjection],
        availableInvocations: @escaping @Sendable (TLAStateProjection) throws -> [TLAActionInvocation],
        validateInvocation: @escaping @Sendable (TLAActionInvocation) -> TLALiveActionRejection.Reason?,
        decodeState: @escaping @Sendable (TLAStateProjection) throws -> Void
    ) {
        self.successors = successors
        self.availableInvocations = availableInvocations
        self.validateInvocation = validateInvocation
        self.decodeState = decodeState
    }
}

/// An immutable handle to the one authoritative live runtime.
///
/// Handle copies share the same storage actor and stable identity, so a
/// commit made through one handle is immediately visible through every other
/// handle of the same runtime. A handle exposes identity, schema, current
/// snapshots, and action execution; it has no shutdown authority and no
/// access to raw formal state. Typed model surfaces convert their generated
/// action labels to invocations and execute through this same entry point.
public struct TLALiveMachine: Sendable {
    public let identity: TLALiveMachineIdentity
    public let schema: MachineSchema
    private let storage: TLALiveMachineStorage

    init(identity: TLALiveMachineIdentity, schema: MachineSchema, storage: TLALiveMachineStorage) {
        self.identity = identity
        self.schema = schema
        self.storage = storage
    }

    public var schemaIdentifier: String { schema.identifier }

    /// The current committed snapshot, or the reason none is available.
    public func current() async -> TLALiveMachineCurrentResult {
        await storage.current()
    }

    /// Attaches a non-owning observer to this existing runtime.
    ///
    /// Attachment captures its initial snapshot and registers delivery in one
    /// storage-actor operation, so an overlapping commit is either part of the
    /// baseline or appears once as the following update.
    public func observe() async -> TLALiveMachineAttachmentOutcome {
        await storage.observe()
    }

    /// Executes a generic invocation through this runtime.
    ///
    /// Execution linearizes at runtime acceptance. The runtime rejects
    /// lifecycle and validation failures before acceptance and then runs a
    /// non-suspending commit path, so caller cancellation has no execution
    /// effect and no cancellation outcome exists.
    public func execute(_ invocation: TLAActionInvocation, requestID: UUID = UUID()) async -> TLALiveActionOutcome {
        await execute(.init(
            requestID: requestID,
            target: identity,
            schemaIdentifier: schema.identifier,
            invocation: invocation
        ))
    }

    /// Executes a full action request through this runtime.
    public func execute(_ request: TLALiveActionRequest) async -> TLALiveActionOutcome {
        await storage.execute(request)
    }
}

/// The declared owner of one live runtime.
///
/// Creation returns the owner, which vends the common handle and holds the
/// only explicit shutdown authority. Ending is idempotent and explicit;
/// releasing non-owner handles never ends an otherwise live runtime.
public final class TLALiveMachineOwner: Sendable {
    private let storage: TLALiveMachineStorage
    public let identity: TLALiveMachineIdentity
    public let schema: MachineSchema

    private init(storage: TLALiveMachineStorage, identity: TLALiveMachineIdentity, schema: MachineSchema) {
        self.storage = storage
        self.identity = identity
        self.schema = schema
    }

    /// Creates a new runtime with a fresh identity, an initial committed
    /// state, and the supplied formal transition driver.
    public static func create(
        schema: MachineSchema,
        initial: TLAStateProjection,
        driver: TLALiveMachineTransitionDriver
    ) -> TLALiveMachineOwner {
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
        driver: TLALiveMachineTransitionDriver,
        observationMailboxCapacity: Int
    ) -> TLALiveMachineOwner {
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
    public var handle: TLALiveMachine {
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
actor TLALiveMachineStorage {
    let identity: TLALiveMachineIdentity
    let schema: MachineSchema
    let driver: TLALiveMachineTransitionDriver
    var state: TLAStateProjection
    var position = TLALiveMachinePosition(value: 0)
    private var isEnded = false
    private let observationMailboxCapacity: Int
    private var subscriptions: [UUID: ObservationSubscriptionState] = [:]
    private let logger = Logger(subsystem: "SwiftTLA", category: "LiveMachine")

    init(
        identity: TLALiveMachineIdentity,
        schema: MachineSchema,
        initial: TLAStateProjection,
        driver: TLALiveMachineTransitionDriver,
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

    func observe() -> TLALiveMachineAttachmentOutcome {
        guard !isEnded else { return .unavailable(.endedByOwner) }
        let subscriptionID = UUID()
        let snapshot = makeSnapshot()
        subscriptions[subscriptionID] = .init(
            events: [.snapshot(snapshot, reason: .attached)],
            continuityAnchor: snapshot.position
        )
        return .attached(.init(identity: identity, subscriptionID: subscriptionID, storage: self))
    }

    func next(_ subscriptionID: UUID) async -> TLALiveMachineObservationEvent? {
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
        let snapshot = makeSnapshot()
        let loss = subscription.loss!
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

    func execute(_ request: TLALiveActionRequest) -> TLALiveActionOutcome {
        guard !isEnded else {
            return rejected(.runtimeUnavailable(.endedByOwner), request: request, current: makeSnapshot())
        }
        let before = makeSnapshot()
        guard request.target == identity else {
            return rejected(.identityMismatch, request: request, current: before)
        }
        guard request.schemaIdentifier == schema.identifier else {
            return rejected(.schemaMismatch, request: request, current: before)
        }
        guard let action = schema.actions.first(where: { $0.id == request.invocation.name }) else {
            return rejected(.unknownAction, request: request, current: before)
        }
        guard action.parameters.count == request.invocation.arguments.count else {
            return rejected(.invalidArity, request: request, current: before)
        }
        if let reason = driver.validateInvocation(request.invocation) {
            return rejected(reason, request: request, current: before)
        }
        let candidates: [TLAStateProjection]
        do {
            candidates = try driver.successors(state, request.invocation)
        } catch {
            return failed(
                code: .evaluationFailed,
                message: String(describing: error),
                request: request,
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
                request: request,
                current: before
            )
        }
        guard let candidate = candidates.first else {
            return rejected(.actionNotEnabled, request: request, current: before)
        }
        do {
            try driver.decodeState(candidate)
        } catch {
            return failed(
                code: .decodeFailed,
                message: String(describing: error),
                request: request,
                current: before
            )
        }
        guard let nextPosition = position.next else {
            return failed(
                code: .positionExhausted,
                message: "The runtime ordering position is exhausted.",
                request: request,
                current: before
            )
        }
        state = candidate
        position = nextPosition
        let after = makeSnapshot()
        let commit = TLALiveMachineCommit(
            requestID: request.requestID,
            invocation: request.invocation,
            before: before,
            after: after
        )
        publish(commit)
        log("committed", request: request)
        return .committed(commit)
    }

    private func publish(_ commit: TLALiveMachineCommit) {
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
        let availability: TLAMachineObservation.Availability
        do {
            availability = .available(try driver.availableInvocations(state))
        } catch {
            availability = .unavailable(.init(
                code: .evaluationFailed,
                message: String(describing: error)
            ))
        }
        return .init(
            identity: identity,
            schemaIdentifier: schema.identifier,
            position: position,
            state: state,
            availability: availability
        )
    }

    private func rejected(
        _ reason: TLALiveActionRejection.Reason,
        request: TLALiveActionRequest,
        current: TLALiveMachineSnapshot
    ) -> TLALiveActionOutcome {
        log("rejected", request: request, detail: "reason=\(reason.code)")
        return .rejected(.init(
            requestID: request.requestID,
            invocation: request.invocation,
            reason: reason,
            current: current
        ))
    }

    private func failed(
        code: TLALiveActionFailure.Code,
        message: String,
        request: TLALiveActionRequest,
        current: TLALiveMachineSnapshot
    ) -> TLALiveActionOutcome {
        log("failed", request: request, detail: "code=\(code.rawValue)")
        return .failed(.init(
            requestID: request.requestID,
            invocation: request.invocation,
            code: code,
            message: message,
            current: current
        ))
    }

    private func log(_ outcome: String, request: TLALiveActionRequest? = nil, detail: String = "") {
        let identityValue = identity.value.uuidString
        let schemaIdentifier = schema.identifier
        let requestID = request?.requestID.uuidString ?? "-"
        let positionValue = position.value
        logger.notice("outcome=\(outcome, privacy: .public) identity=\(identityValue, privacy: .public) schema=\(schemaIdentifier, privacy: .public) request=\(requestID, privacy: .public) position=\(positionValue, privacy: .public) detail=\(detail, privacy: .public)")
    }
}

private struct ObservationSubscriptionState {
    var events: [TLALiveMachineObservationEvent]
    var ordinaryUpdateCount = 0
    var continuityAnchor: TLALiveMachinePosition
    var isLossPending = false
    var loss: TLALiveMachineObservationLoss?
    var isClosed = false
    var waiter: CheckedContinuation<TLALiveMachineObservationEvent?, Never>?

    init(events: [TLALiveMachineObservationEvent], continuityAnchor: TLALiveMachinePosition) {
        self.events = events
        self.continuityAnchor = continuityAnchor
    }

    mutating func enqueueUpdate(
        _ commit: TLALiveMachineCommit,
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

    mutating func enqueueControl(_ event: TLALiveMachineObservationEvent) {
        events.append(event)
    }

    mutating func didDeliver(_ event: TLALiveMachineObservationEvent) {
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

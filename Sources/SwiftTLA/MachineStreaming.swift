import Foundation

/// A committed, ordered machine observation suitable for generic tooling.
public struct TLAMachineUpdate: Sendable, Equatable {
    public enum Cause: Sendable, Equatable {
        case initial
        case transition(TLAActionInvocation)
    }

    public let machineID: UUID
    public let sequence: UInt64
    public let cause: Cause
    public let observation: TLAMachineObservation

    public init(machineID: UUID, sequence: UInt64, cause: Cause, observation: TLAMachineObservation) {
        self.machineID = machineID
        self.sequence = sequence
        self.cause = cause
        self.observation = observation
    }
}

/// A machine owner capable of delivering a race-free initial observation and
/// later committed updates. Consumers use sequence gaps to detect dropped data.
public protocol TLAMachineStreaming: TLAMachineObserving {
    var machineID: UUID { get async }
    func machineUpdates() async -> AsyncStream<TLAMachineUpdate>
}

/// Reference-owned live access for a generated value machine.
///
/// Keeping continuations here preserves generated model value semantics while
/// providing one serialization point for observation, execution, and updates.
public actor TLAMachineSession<Model>: TLAMachineStreaming
where Model: TLAMachineAdapterCanonicalModel & TLAMachineSchemaProviding {
    public nonisolated let machineID: UUID
    public let schema: MachineSchema

    private var machine: Model
    /// Sequence of the latest committed transition. Initial snapshots use the
    /// current value so adding another subscriber never creates a false gap.
    private var sequence: UInt64 = 0
    private var continuations: [UUID: AsyncStream<TLAMachineUpdate>.Continuation] = [:]

    public init(_ machine: Model, machineID: UUID = UUID()) {
        self.machine = machine
        self.machineID = machineID
        self.schema = Model.machineSchema
    }

    public func machineObservation() -> TLAMachineObservation {
        machine.synchronousMachineObservation()
    }

    public func machineUpdates() -> AsyncStream<TLAMachineUpdate> {
        let subscriberID = UUID()
        let initial = makeUpdate(cause: .initial)
        let session = self
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            continuations[subscriberID] = continuation
            continuation.onTermination = { _ in
                Task { await session.removeSubscriber(subscriberID) }
            }
            continuation.yield(initial)
        }
    }

    public func execute(_ invocation: TLAActionInvocation) throws -> Model.TransitionResult {
        let result = try machine.executeSynchronously(invocation)
        publish(cause: .transition(invocation))
        return result
    }

    private func makeUpdate(cause: TLAMachineUpdate.Cause) -> TLAMachineUpdate {
        .init(machineID: machineID, sequence: sequence, cause: cause, observation: machine.synchronousMachineObservation())
    }

    private func publish(cause: TLAMachineUpdate.Cause) {
        sequence &+= 1
        let update = makeUpdate(cause: cause)
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

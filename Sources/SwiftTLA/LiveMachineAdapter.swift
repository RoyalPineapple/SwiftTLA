import Foundation

/// The lifecycle state of an observable adapter's locally derived cache.
package enum TLALiveMachineAdapterStatus: Sendable, Equatable {
    case attaching
    case current(TLALiveMachinePosition)
    case recovering(TLALiveMachineObservationLoss)
    case terminated(TLALiveMachineTermination)
    case invalidEvent(String)
}

/// A typed state derived from one contiguous live-runtime observation.
package struct TLALiveMachineAdapterSnapshot<State: Sendable & Equatable>: Sendable, Equatable {
    public let identity: TLALiveMachineIdentity
    public let position: TLALiveMachinePosition
    public let state: State

    public init(identity: TLALiveMachineIdentity, position: TLALiveMachinePosition, state: State) {
        self.identity = identity
        self.position = position
        self.state = state
    }
}

/// The single event reducer for a generated observable adapter.
/// Action requests never mutate this cache. Only subscription events can do so.
@MainActor
package final class TLALiveMachineObservableReducer<State: Sendable & Equatable, Action: Sendable & Equatable>: Sendable {
    public private(set) var status: TLALiveMachineAdapterStatus = .attaching
    public private(set) var current: TLALiveMachineAdapterSnapshot<State>?

    private let identity: TLALiveMachineIdentity
    private let decode: @Sendable (GeneratedMachineStorage.State) throws -> State

    public init(
        identity: TLALiveMachineIdentity,
        decode: @escaping @Sendable (GeneratedMachineStorage.State) throws -> State
    ) {
        self.identity = identity
        self.decode = decode
    }

    @discardableResult
    public func reduce(_ event: TLALiveMachineObservationEvent<Action>) -> TLALiveMachineCommit<Action>? {
        switch event {
        case .snapshot(let snapshot, _):
            guard validate(snapshot) else { return nil }
            do {
                current = .init(identity: identity, position: snapshot.position, state: try decode(snapshot.state))
                status = .current(snapshot.position)
            } catch {
                current = nil
                status = .invalidEvent("The runtime snapshot could not decode as the generated State: \(error)")
            }
            return nil
        case .update(let commit):
            guard validate(commit.before), validate(commit.after) else { return nil }
            guard case .current(let position) = status, position == commit.before.position,
                  commit.after.position == commit.before.position.next else {
                current = nil
                status = .invalidEvent("The runtime update was not contiguous with the adapter cache.")
                return nil
            }
            do {
                current = .init(identity: identity, position: commit.after.position, state: try decode(commit.after.state))
                status = .current(commit.after.position)
                return commit
            } catch {
                current = nil
                status = .invalidEvent("The committed runtime state could not decode as the generated State: \(error)")
                return nil
            }
        case .loss(let loss):
            guard loss.identity == identity else {
                current = nil
                status = .invalidEvent("The observation loss belongs to a different runtime identity.")
                return nil
            }
            current = nil
            status = .recovering(loss)
            return nil
        case .terminated(let termination):
            guard termination.identity == identity else {
                current = nil
                status = .invalidEvent("The termination belongs to a different runtime identity.")
                return nil
            }
            current = nil
            status = .terminated(termination)
            return nil
        }
    }

    private func validate(_ snapshot: TLALiveMachineSnapshot) -> Bool {
        guard snapshot.identity == identity else {
            current = nil
            status = .invalidEvent("The observation belongs to a different runtime identity.")
            return false
        }
        return true
    }
}

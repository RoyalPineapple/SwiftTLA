import Foundation
import Testing
@testable import SwiftTLA

@Suite("Live machine observation")
struct LiveMachineObservationTests {
    private static let countToken = TLAStateProjection.Token(validating: "count")!
    private static let schema = MachineSchema(
        identifier: "live-machine-observation-tests.counter-v1",
        model: .init(name: "ObservationCounter"),
        state: [.init(id: "count", display: .init(name: "count"), value: .integer, swiftType: "Int")],
        actions: [.init(id: "advance", display: .init(name: "advance"), parameters: [])]
    )

    private static func makeOwner(capacity: Int = 64) throws -> TLALiveMachineOwner {
        let initial = try TLAStateProjection(validating: [
            .init(token: countToken, value: .int(0))
        ])
        let driver = TLALiveMachineTransitionDriver(
            successors: { projection, invocation in
                guard invocation.name == "advance" else { return [] }
                guard case .int(let count)? = projection.value(for: countToken) else { return [] }
                return [try TLAStateProjection(validating: [
                    .init(token: countToken, value: .int(count + 1))
                ])]
            },
            availableInvocations: { _ in [.init(name: "advance")] },
            validateInvocation: { invocation in invocation.name == "advance" ? nil : .unknownAction },
            decodeState: { _ in }
        )
        return TLALiveMachineOwner.create(
            schema: schema,
            initial: initial,
            driver: driver,
            observationMailboxCapacity: capacity
        )
    }

    private static func attached(
        _ machine: TLALiveMachine
    ) async throws -> TLALiveMachineObservationSubscription {
        guard case .attached(let subscription) = await machine.observe() else {
            throw ObservationTestError.expectedAttachment
        }
        return subscription
    }

    private static func next(
        _ iterator: inout TLALiveMachineObservationSubscription.AsyncIterator
    ) async throws -> TLALiveMachineObservationEvent {
        try #require(await iterator.next())
    }

    @Test("Attachment is an atomic baseline of the existing runtime")
    func attachmentAfterPriorCommitUsesExistingRuntime() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        _ = await machine.execute(.init(name: "advance"), requestID: UUID())

        let subscription = try await Self.attached(machine)
        var iterator = subscription.makeAsyncIterator()
        let event = try await Self.next(&iterator)

        guard case .snapshot(let snapshot, reason: .attached) = event else {
            Issue.record("Expected attached snapshot, found \(event)")
            return
        }
        #expect(snapshot.identity == machine.identity)
        #expect(snapshot.position == .init(value: 1))
        #expect(snapshot.state.value(for: Self.countToken) == .int(1))
    }

    @Test("Attachment baseline is followed by commits in runtime order")
    func attachmentThenCommitDeliversOneOrderedUpdate() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let subscription = try await Self.attached(machine)
        var iterator = subscription.makeAsyncIterator()

        let baseline = try await Self.next(&iterator)
        _ = await machine.execute(.init(name: "advance"), requestID: UUID())
        let update = try await Self.next(&iterator)

        guard case .snapshot(let snapshot, reason: .attached) = baseline,
              case .update(let commit) = update else {
            Issue.record("Expected baseline then update")
            return
        }
        #expect(snapshot.position == .init(value: 0))
        #expect(commit.before == snapshot)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.identity == subscription.identity)
    }

    @Test("Overflow is explicit and recovery establishes a new baseline")
    func overflowRequiresResynchronization() async throws {
        let owner = try Self.makeOwner(capacity: 1)
        let machine = owner.handle
        let subscription = try await Self.attached(machine)
        var iterator = subscription.makeAsyncIterator()
        _ = try await Self.next(&iterator)

        _ = await machine.execute(.init(name: "advance"), requestID: UUID())
        _ = await machine.execute(.init(name: "advance"), requestID: UUID())

        let lossEvent = try await Self.next(&iterator)
        guard case .loss(let loss) = lossEvent else {
            Issue.record("Expected explicit loss, found \(lossEvent)")
            return
        }
        #expect(loss.identity == machine.identity)
        #expect(loss.lastContiguousPosition == .init(value: 0))
        #expect(loss.latestKnownPosition == .init(value: 2))

        #expect(await subscription.resynchronize() == .resumed(at: .init(value: 2)))
        let recovered = try await Self.next(&iterator)
        guard case .snapshot(let snapshot, reason: .resynchronized(after: loss)) = recovered else {
            Issue.record("Expected resynchronization snapshot, found \(recovered)")
            return
        }
        #expect(snapshot.position == .init(value: 2))
        #expect(snapshot.state.value(for: Self.countToken) == .int(2))
        #expect(loss.lastContiguousPosition == .init(value: 0))

        _ = await machine.execute(.init(name: "advance"), requestID: UUID())
        let update = try await Self.next(&iterator)
        guard case .update(let commit) = update else {
            Issue.record("Expected ordered post-recovery update")
            return
        }
        #expect(commit.before == snapshot)
        #expect(commit.after.position == .init(value: 3))
    }

    @Test("Cancelling one subscription leaves peers and runtime live")
    func cancellationIsSubscriptionLocal() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let cancelled = try await Self.attached(machine)
        let peer = try await Self.attached(machine)
        var cancelledIterator = cancelled.makeAsyncIterator()
        var peerIterator = peer.makeAsyncIterator()
        _ = try await Self.next(&cancelledIterator)
        _ = try await Self.next(&peerIterator)

        await cancelled.cancel()
        #expect(await cancelledIterator.next() == nil)
        _ = await machine.execute(.init(name: "advance"), requestID: UUID())

        let peerEvent = try await Self.next(&peerIterator)
        guard case .update(let commit) = peerEvent else {
            Issue.record("Expected peer update, found \(peerEvent)")
            return
        }
        #expect(commit.after.position == .init(value: 1))
        guard case .snapshot(let current) = await machine.current() else {
            Issue.record("Expected live runtime")
            return
        }
        #expect(current.position == .init(value: 1))
    }

    @Test("Owner shutdown fans out one terminal event and rejects later attachment")
    func ownerShutdownTerminatesAttachedObservers() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let first = try await Self.attached(machine)
        let second = try await Self.attached(machine)
        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        _ = try await Self.next(&firstIterator)
        _ = try await Self.next(&secondIterator)

        await owner.end()
        let firstEvent = try await Self.next(&firstIterator)
        let secondEvent = try await Self.next(&secondIterator)
        guard case .terminated(let firstTermination) = firstEvent,
              case .terminated(let secondTermination) = secondEvent else {
            Issue.record("Expected terminal fan-out")
            return
        }
        #expect(firstTermination.identity == machine.identity)
        #expect(firstTermination.finalPosition == .init(value: 0))
        #expect(firstTermination == secondTermination)
        #expect(await firstIterator.next() == nil)
        #expect(await secondIterator.next() == nil)
        guard case .unavailable(.endedByOwner) = await machine.observe() else {
            Issue.record("Expected ended runtime to reject attachment")
            return
        }
    }

    @Test("Observation values remain Sendable")
    func publicObservationValuesAreSendable() {
        func requireSendable<Value: Sendable>(_: Value.Type) {}
        requireSendable(TLALiveMachineObservationEvent.self)
        requireSendable(TLALiveMachineObservationSubscription.self)
        requireSendable(TLALiveMachineObservationSubscription.AsyncIterator.self)
    }
}

private enum ObservationTestError: Error {
    case expectedAttachment
}

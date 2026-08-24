import Foundation
import Testing
@testable import SwiftTLA

private enum LiveMachineTestError: Error {
    case evaluationUnavailable
}

private enum CounterAction: Hashable, Sendable {
    case advance
    case step(Int)
}

@Suite("Live machine runtime")
struct LiveMachineRuntimeTests {
    private struct Fixture {
        let storage: _GeneratedMachineStorage
        let owner: TLALiveMachineOwner<CounterAction>

        func count(in state: _GeneratedMachineStorage.State) throws -> Int {
            try storage.value(at: 0, in: state)
        }
    }

    private static func counterSpec() -> TLASpec {
        let count = Var<Int>("count")
        return TLASpec("LiveCounter") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 3) }
            Action("step", parameters: [ActionParameter<Int>("delta", values: [1, 2])]) {
                ActionExpr.assign(.named("count"), .add(.variable("count"), .variable("delta")))
            }
        }
    }

    private static func transitionDriver(
        storage: _GeneratedMachineStorage,
        successors: (@Sendable (_GeneratedMachineStorage.State, CounterAction) throws -> [_GeneratedMachineStorage.State])? = nil,
        decodeState: @escaping @Sendable (_GeneratedMachineStorage.State) throws -> Void = { _ in }
    ) -> TLALiveMachineTransitionDriver<CounterAction> {
        return TLALiveMachineTransitionDriver(
            successors: successors ?? realSuccessors(storage),
            decodeState: decodeState
        )
    }

    private static func realSuccessors(
        _ storage: _GeneratedMachineStorage
    ) -> @Sendable (_GeneratedMachineStorage.State, CounterAction) throws -> [_GeneratedMachineStorage.State] {
        return { state, action in
            let (ordinal, arguments): (Int, [TLAValue]) = switch action {
            case .advance: (0, [])
            case .step(let delta): (1, [.int(delta)])
            }
            return try storage.successors(
                actionOrdinal: ordinal,
                arguments: arguments,
                from: state
            )
        }
    }

    private static func makeFixture(
        initialCount: Int = 0,
        driver: ((_GeneratedMachineStorage) throws -> TLALiveMachineTransitionDriver<CounterAction>)? = nil
    ) throws -> Fixture {
        let storage = _GeneratedMachineStorage(compilation: try counterSpec().compile())
        let initial = try storage.initialState {
            let count: Int = try storage.value(at: 0, in: $0)
            return count == initialCount
        }
        let resolvedDriver = try driver?(storage) ?? transitionDriver(storage: storage)
        return .init(
            storage: storage,
            owner: TLALiveMachineOwner.create(
                initial: initial,
                driver: resolvedDriver
            )
        )
    }

    private static func requireCurrentSnapshot(
        from machine: TLALiveMachine<CounterAction>
    ) async -> TLALiveMachineSnapshot? {
        guard case .snapshot(let snapshot) = await machine.current() else { return nil }
        return snapshot
    }

    @Test("Requests after owner termination are rejected without commit")
    func terminatedRuntimeRejectsWithoutCommit() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        await owner.end()
        let requestID = UUID()

        #expect(await machine.current() == .unavailable(.endedByOwner))

        let outcome = await machine.execute(.advance, requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            action: .advance,
            reason: .runtimeUnavailable(.endedByOwner),
            current: before
        )))
        await owner.end()
        #expect(await machine.current() == .unavailable(.endedByOwner))
    }


    @Test("A disabled action is rejected before acceptance and commits nothing")
    func disabledActionRejectsWithoutCommit() async throws {
        let fixture = try Self.makeFixture(initialCount: 2)
        let owner = fixture.owner
        let machine = owner.handle
        _ = await machine.execute(.advance, requestID: UUID())
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        #expect(try fixture.count(in: before.state) == 3)
        #expect(before.position == .init(value: 1))
        let requestID = UUID()

        let outcome = await machine.execute(.advance, requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            action: .advance,
            reason: .actionNotEnabled,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("An accepted evaluation failure leaves state and position unchanged")
    func evaluationFailureKeepsStateAndPosition() async throws {
        let fixture = try Self.makeFixture { storage in
            Self.transitionDriver(
                storage: storage,
                successors: { _, _ in throw LiveMachineTestError.evaluationUnavailable }
            )
        }
        let owner = fixture.owner
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()

        let outcome = await machine.execute(.advance, requestID: requestID)

        guard case .failed(let failure) = outcome else {
            Issue.record("Expected a normal failure, found \(outcome)")
            return
        }
        #expect(failure.requestID == requestID)
        #expect(failure.code == .evaluationFailed)
        #expect(failure.current == before)
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("An accepted decode failure leaves state and position unchanged")
    func decodeFailureKeepsStateAndPosition() async throws {
        let fixture = try Self.makeFixture { storage in
            Self.transitionDriver(
                storage: storage,
                successors: Self.realSuccessors(storage),
                decodeState: { _ in throw LiveMachineTestError.evaluationUnavailable }
            )
        }
        let owner = fixture.owner
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()

        let outcome = await machine.execute(.advance, requestID: requestID)

        guard case .failed(let failure) = outcome else {
            Issue.record("Expected a normal failure, found \(outcome)")
            return
        }
        #expect(failure.requestID == requestID)
        #expect(failure.code == .decodeFailed)
        #expect(failure.current == before)
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("Generated actions require one successor")
    func ambiguousActionFailsWithoutCommitAndDeterministicActionCommits() async throws {
        let fixture = try Self.makeFixture { storage in
            let firstCandidate = try storage.initialState { try storage.value(at: 0, in: $0) == 1 }
            let secondCandidate = try storage.initialState { try storage.value(at: 0, in: $0) == 2 }
            do {
                _ = try _GeneratedMachineStorage.onlySuccessor([firstCandidate, secondCandidate])
                Issue.record("Expected an ambiguous action")
            } catch GeneratedMachineError.ambiguousAction {
            }
            return Self.transitionDriver(
                storage: storage,
                successors: { state, action in
                    if case .step(_) = action {
                        return [firstCandidate, secondCandidate]
                    }
                    return try Self.realSuccessors(storage)(state, action)
                }
            )
        }
        let owner = fixture.owner
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))

        let ambiguousRequestID = UUID()
        let ambiguousOutcome = await machine.execute(.step(1), requestID: ambiguousRequestID)

        guard case .failed(let failure) = ambiguousOutcome else {
            Issue.record("Expected an ambiguous-action failure, found \(ambiguousOutcome)")
            return
        }
        #expect(failure.requestID == ambiguousRequestID)
        #expect(failure.code == .ambiguousAction)
        #expect(failure.message.contains("2 successor"))
        #expect(failure.current == before)
        #expect(await machine.current() == .snapshot(before))

        let commitRequestID = UUID()
        let commitOutcome = await machine.execute(.advance, requestID: commitRequestID)

        guard case .committed(let commit) = commitOutcome else {
            Issue.record("Expected a committed transition, found \(commitOutcome)")
            return
        }
        #expect(commit.requestID == commitRequestID)
        #expect(commit.before == before)
        #expect(try fixture.count(in: commit.after.state) == 1)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("A committed transition advances state and position together and binds identity and schema")
    func committedTransitionAdvancesStateAndPositionAtomically() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()

        let outcome = await machine.execute(.advance, requestID: requestID)

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(commit.action == .advance)
        #expect(commit.before == before)
        #expect(commit.before.identity == owner.identity)
        #expect(commit.before.position == .init(value: 0))
        #expect(try fixture.count(in: commit.before.state) == 0)
        #expect(commit.after.identity == owner.identity)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(try fixture.count(in: commit.after.state) == 1)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Parameterized actions commit exactly once per accepted request")
    func parameterizedActionsCommitExactlyOncePerRequest() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let machine = owner.handle

        let first = await machine.execute(.step(2), requestID: UUID())
        guard case .committed(let firstCommit) = first else {
            Issue.record("Expected a committed transition, found \(first)")
            return
        }
        #expect(try fixture.count(in: firstCommit.before.state) == 0)
        #expect(firstCommit.before.position == .init(value: 0))
        #expect(try fixture.count(in: firstCommit.after.state) == 2)
        #expect(firstCommit.after.position == .init(value: 1))
        #expect(firstCommit.after.position == firstCommit.before.position.next)

        let second = await machine.execute(.step(1), requestID: UUID())
        guard case .committed(let secondCommit) = second else {
            Issue.record("Expected a committed transition, found \(second)")
            return
        }
        #expect(secondCommit.before == firstCommit.after)
        #expect(try fixture.count(in: secondCommit.after.state) == 3)
        #expect(secondCommit.after.position == .init(value: 2))
        #expect(secondCommit.after.position == secondCommit.before.position.next)
        #expect(await machine.current() == .snapshot(secondCommit.after))
    }

    @Test("Shared handles converge on one runtime state without reattachment")
    func sharedHandlesConvergeOnOneRuntimeState() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let first = owner.handle
        let second = owner.handle

        #expect(first.identity == second.identity)
        #expect(first.identity == owner.identity)

        let outcome = await first.execute(.advance, requestID: UUID())
        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }

        #expect(commit.after.identity == second.identity)
        #expect(await second.current() == .snapshot(commit.after))
        let secondCurrent = await second.current()
        let firstCurrent = await first.current()
        #expect(secondCurrent == firstCurrent)
    }

    @Test("Releasing one of several handles never ends an otherwise live runtime")
    func releasingASecondHandleKeepsRuntimeAvailable() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let primary = owner.handle

        var secondary: TLALiveMachine<CounterAction>? = owner.handle
        #expect(secondary?.identity == owner.identity)
        _ = await secondary?.execute(.advance, requestID: UUID())
        secondary = nil

        let current = try #require(await Self.requireCurrentSnapshot(from: primary))
        #expect(current.identity == owner.identity)
        #expect(try fixture.count(in: current.state) == 1)
        #expect(current.position == .init(value: 1))

        let outcome = await primary.execute(.advance, requestID: UUID())
        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }
        #expect(try fixture.count(in: commit.after.state) == 2)
        #expect(commit.after.position == .init(value: 2))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await primary.current() == .snapshot(commit.after))
    }

    @Test("Distinct runtime identities isolate state and position")
    func distinctRuntimesIsolateStateAndPosition() async throws {
        let fixtureA = try Self.makeFixture()
        let fixtureB = try Self.makeFixture()
        let ownerA = fixtureA.owner
        let ownerB = fixtureB.owner
        let machineA = ownerA.handle
        let machineB = ownerB.handle

        #expect(ownerA.identity != ownerB.identity)

        _ = await machineA.execute(.advance, requestID: UUID())
        _ = await machineA.execute(.advance, requestID: UUID())

        let currentA = try #require(await Self.requireCurrentSnapshot(from: machineA))
        let currentB = try #require(await Self.requireCurrentSnapshot(from: machineB))
        #expect(try fixtureA.count(in: currentA.state) == 2)
        #expect(currentA.position == .init(value: 2))
        #expect(currentA.identity == ownerA.identity)
        #expect(try fixtureB.count(in: currentB.state) == 0)
        #expect(currentB.position == .init(value: 0))
        #expect(currentB.identity == ownerB.identity)
    }

    @Test("Caller cancellation after acceptance still commits exactly once")
    func cancellationAfterAcceptanceStillCommits() async throws {
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let fixture = try Self.makeFixture { storage in
            Self.transitionDriver(
                storage: storage,
                successors: { state, action in
                    signal.yield(())
                    return try Self.realSuccessors(storage)(state, action)
                }
            )
        }
        let owner = fixture.owner
        let machine = owner.handle
        let requestID = UUID()
        var iterator = accepted.makeAsyncIterator()

        let task = Task { await machine.execute(.advance, requestID: requestID) }
        await iterator.next()
        task.cancel()
        let outcome = await task.value

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected the accepted request to commit, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(try fixture.count(in: commit.before.state) == 0)
        #expect(commit.before.position == .init(value: 0))
        #expect(try fixture.count(in: commit.after.state) == 1)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Caller cancellation after acceptance still resolves to the accepted normal failure")
    func cancellationAfterAcceptanceStillFailsNormally() async throws {
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let fixture = try Self.makeFixture { storage in
            Self.transitionDriver(
                storage: storage,
                successors: { _, _ in
                    signal.yield(())
                    throw LiveMachineTestError.evaluationUnavailable
                }
            )
        }
        let owner = fixture.owner
        let machine = owner.handle
        let requestID = UUID()
        var iterator = accepted.makeAsyncIterator()

        let task = Task { await machine.execute(.advance, requestID: requestID) }
        await iterator.next()
        task.cancel()
        let outcome = await task.value

        guard case .failed(let failure) = outcome else {
            Issue.record("Expected a normal failure, found \(outcome)")
            return
        }
        #expect(failure.requestID == requestID)
        #expect(failure.code == .evaluationFailed)
        #expect(try fixture.count(in: failure.current.state) == 0)
        #expect(failure.current.position == .init(value: 0))
        #expect(await machine.current() == .snapshot(failure.current))
    }

    @Test("Cancellation before the caller awaits cannot erase the accepted outcome")
    func cancellationBeforeAwaitStillCommits() async throws {
        let fixture = try Self.makeFixture()
        let owner = fixture.owner
        let machine = owner.handle
        let requestID = UUID()

        let task = Task { await machine.execute(.advance, requestID: requestID) }
        task.cancel()
        let outcome = await task.value

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected the request to commit, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(try fixture.count(in: commit.after.state) == 1)
        #expect(commit.after.position == .init(value: 1))
        #expect(await machine.current() == .snapshot(commit.after))
    }
}

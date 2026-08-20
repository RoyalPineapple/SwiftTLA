import Foundation
import Testing
@testable import SwiftTLA

private enum LiveMachineTestError: Error {
    case evaluationUnavailable
    case invalidToken
}

private enum CounterAction: Hashable, Sendable {
    case advance
    case step(Int)
}

@Suite("Live machine runtime")
struct LiveMachineRuntimeTests {
    private static func countToken() throws -> TLAStateProjection.Token {
        guard let token = TLAStateProjection.Token(validating: "count") else {
            throw LiveMachineTestError.invalidToken
        }
        return token
    }

    private static let counterSchema = MachineSchema(
        identifier: "live-machine-runtime-tests.counter-v1",
        model: .init(name: "LiveCounter"),
        state: [.init(id: "count", display: .init(name: "count"), value: .integer, swiftType: "Int")],
        actions: [
            .init(id: "advance", display: .init(name: "advance"), parameters: []),
            .init(
                id: "step",
                display: .init(name: "step"),
                parameters: [.init(id: "delta", display: .init(name: "delta"), value: .integer, swiftType: "Int")]
            )
        ]
    )

    private static func counterSpec() -> TLASpec {
        let count = Var<Int>("count")
        return TLASpec("LiveCounter") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 3) }
            Action("step", parameters: [ActionParameter<Int>("delta", values: [1, 2])]) {
                ActionExpr.assign("count", .add(.variable("count"), .variable("delta")))
            }
        }
    }

    private static func transitionDriver(
        compilation: CompiledSpecification,
        successors: (@Sendable (TLAStateProjection, CounterAction) throws -> [TLAStateProjection])? = nil,
        decodeState: @escaping @Sendable (TLAStateProjection) throws -> Void = { _ in }
    ) -> TLALiveMachineTransitionDriver<CounterAction> {
        let executor = actionExecutor(compilation)
        return TLALiveMachineTransitionDriver(
            successors: successors ?? { projection, action in
                try executor.successors(for: action, from: projection)
            },
            validateAction: { _ in nil },
            decodeState: decodeState
        )
    }

    private static func actionExecutor(_ compilation: CompiledSpecification) -> CompiledActionExecutor<CounterAction> {
        .init(
            compilation: compilation,
            actionOrdinal: { action in
                switch action {
                case .advance: 0
                case .step: 1
                }
            },
            arguments: { action in
                switch action {
                case .advance: []
                case .step(let delta): [.int(delta)]
                }
            },
            label: { ordinal, arguments in
                switch (ordinal, arguments) {
                case (0, []): .advance
                case (1, [.int(let delta)]): .step(delta)
                default: nil
                }
            }
        )
    }

    private static func realSuccessors(
        _ compilation: CompiledSpecification
    ) -> @Sendable (TLAStateProjection, CounterAction) throws -> [TLAStateProjection] {
        let executor = actionExecutor(compilation)
        return { projection, action in try executor.successors(for: action, from: projection) }
    }

    private static func makeOwner(
        initialCount: Int = 0,
        driver: TLALiveMachineTransitionDriver<CounterAction>? = nil
    ) throws -> TLALiveMachineOwner<CounterAction> {
        let resolvedDriver: TLALiveMachineTransitionDriver<CounterAction>
        if let driver {
            resolvedDriver = driver
        } else {
            resolvedDriver = transitionDriver(compilation: try counterSpec().compile())
        }
        let initial = try TLAStateProjection(validating: [
            .init(token: try countToken(), value: .int(initialCount))
        ])
        return TLALiveMachineOwner.create(
            schema: counterSchema,
            initial: initial,
            driver: resolvedDriver
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
        let owner = try Self.makeOwner()
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
        let owner = try Self.makeOwner(initialCount: 2)
        let machine = owner.handle
        _ = await machine.execute(.advance, requestID: UUID())
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        #expect(before.state.value(for: try Self.countToken()) == .int(3))
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
        let compilation = try Self.counterSpec().compile()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            compilation: compilation,
            successors: { _, _ in throw LiveMachineTestError.evaluationUnavailable }
        ))
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
        let compilation = try Self.counterSpec().compile()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            compilation: compilation,
            successors: Self.realSuccessors(compilation),
            decodeState: { _ in throw TLAStateProjectionDiagnostic.typeMismatch(
                path: "count",
                expected: "Int",
                actual: .int(0)
            ) }
        ))
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

    @Test("Multiple formal successors fail without commit while a deterministic successor still commits")
    func ambiguousSuccessorsFailWithoutCommitAndDeterministicSuccessorCommits() async throws {
        let compilation = try Self.counterSpec().compile()
        let firstCandidate = try TLAStateProjection(validating: [
            .init(token: try Self.countToken(), value: .int(1))
        ])
        let secondCandidate = try TLAStateProjection(validating: [
            .init(token: try Self.countToken(), value: .int(2))
        ])
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            compilation: compilation,
            successors: { projection, action in
                if case .step(_) = action {
                    return [firstCandidate, secondCandidate]
                }
                return try Self.realSuccessors(compilation)(projection, action)
            }
        ))
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))

        let ambiguousRequestID = UUID()
        let ambiguousOutcome = await machine.execute(.step(1), requestID: ambiguousRequestID)

        guard case .failed(let failure) = ambiguousOutcome else {
            Issue.record("Expected an ambiguous-successors failure, found \(ambiguousOutcome)")
            return
        }
        #expect(failure.requestID == ambiguousRequestID)
        #expect(failure.code == .ambiguousSuccessors)
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
        #expect(commit.after.state.value(for: try Self.countToken()) == .int(1))
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("A committed transition advances state and position together and binds identity and schema")
    func committedTransitionAdvancesStateAndPositionAtomically() async throws {
        let owner = try Self.makeOwner()
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
        #expect(commit.before.schemaIdentifier == Self.counterSchema.identifier)
        #expect(commit.before.position == .init(value: 0))
        #expect(commit.before.state.value(for: try Self.countToken()) == .int(0))
        #expect(commit.after.identity == owner.identity)
        #expect(commit.after.schemaIdentifier == Self.counterSchema.identifier)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(commit.after.state.value(for: try Self.countToken()) == .int(1))
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Parameterized actions commit exactly once per accepted request")
    func parameterizedActionsCommitExactlyOncePerRequest() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle

        let first = await machine.execute(.step(2), requestID: UUID())
        guard case .committed(let firstCommit) = first else {
            Issue.record("Expected a committed transition, found \(first)")
            return
        }
        #expect(firstCommit.before.state.value(for: try Self.countToken()) == .int(0))
        #expect(firstCommit.before.position == .init(value: 0))
        #expect(firstCommit.after.state.value(for: try Self.countToken()) == .int(2))
        #expect(firstCommit.after.position == .init(value: 1))
        #expect(firstCommit.after.position == firstCommit.before.position.next)

        let second = await machine.execute(.step(1), requestID: UUID())
        guard case .committed(let secondCommit) = second else {
            Issue.record("Expected a committed transition, found \(second)")
            return
        }
        #expect(secondCommit.before == firstCommit.after)
        #expect(secondCommit.after.state.value(for: try Self.countToken()) == .int(3))
        #expect(secondCommit.after.position == .init(value: 2))
        #expect(secondCommit.after.position == secondCommit.before.position.next)
        #expect(await machine.current() == .snapshot(secondCommit.after))
    }

    @Test("Shared handles converge on one runtime state without reattachment")
    func sharedHandlesConvergeOnOneRuntimeState() async throws {
        let owner = try Self.makeOwner()
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
        #expect(await second.current() == await first.current())
    }

    @Test("Releasing one of several handles never ends an otherwise live runtime")
    func releasingASecondHandleKeepsRuntimeAvailable() async throws {
        let owner = try Self.makeOwner()
        let primary = owner.handle

        var secondary: TLALiveMachine<CounterAction>? = owner.handle
        #expect(secondary?.identity == owner.identity)
        _ = await secondary?.execute(.advance, requestID: UUID())
        secondary = nil

        let current = try #require(await Self.requireCurrentSnapshot(from: primary))
        #expect(current.identity == owner.identity)
        #expect(current.schemaIdentifier == Self.counterSchema.identifier)
        #expect(current.state.value(for: try Self.countToken()) == .int(1))
        #expect(current.position == .init(value: 1))

        let outcome = await primary.execute(.advance, requestID: UUID())
        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }
        #expect(commit.after.state.value(for: try Self.countToken()) == .int(2))
        #expect(commit.after.position == .init(value: 2))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await primary.current() == .snapshot(commit.after))
    }

    @Test("Distinct runtime identities isolate state and position")
    func distinctRuntimesIsolateStateAndPosition() async throws {
        let ownerA = try Self.makeOwner()
        let ownerB = try Self.makeOwner()
        let machineA = ownerA.handle
        let machineB = ownerB.handle

        #expect(ownerA.identity != ownerB.identity)

        _ = await machineA.execute(.advance, requestID: UUID())
        _ = await machineA.execute(.advance, requestID: UUID())

        let currentA = try #require(await Self.requireCurrentSnapshot(from: machineA))
        let currentB = try #require(await Self.requireCurrentSnapshot(from: machineB))
        #expect(currentA.state.value(for: try Self.countToken()) == .int(2))
        #expect(currentA.position == .init(value: 2))
        #expect(currentA.identity == ownerA.identity)
        #expect(currentB.state.value(for: try Self.countToken()) == .int(0))
        #expect(currentB.position == .init(value: 0))
        #expect(currentB.identity == ownerB.identity)
    }

    @Test("Caller cancellation after acceptance still commits exactly once")
    func cancellationAfterAcceptanceStillCommits() async throws {
        let compilation = try Self.counterSpec().compile()
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            compilation: compilation,
            successors: { projection, action in
                signal.yield(())
                return try Self.realSuccessors(compilation)(projection, action)
            }
        ))
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
        #expect(commit.before.state.value(for: try Self.countToken()) == .int(0))
        #expect(commit.before.position == .init(value: 0))
        #expect(commit.after.state.value(for: try Self.countToken()) == .int(1))
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Caller cancellation after acceptance still resolves to the accepted normal failure")
    func cancellationAfterAcceptanceStillFailsNormally() async throws {
        let compilation = try Self.counterSpec().compile()
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            compilation: compilation,
            successors: { _, _ in
                signal.yield(())
                throw LiveMachineTestError.evaluationUnavailable
            }
        ))
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
        #expect(failure.current.state.value(for: try Self.countToken()) == .int(0))
        #expect(failure.current.position == .init(value: 0))
        #expect(await machine.current() == .snapshot(failure.current))
    }

    @Test("Cancellation before the caller awaits cannot erase the accepted outcome")
    func cancellationBeforeAwaitStillCommits() async throws {
        let owner = try Self.makeOwner()
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
        #expect(commit.after.state.value(for: try Self.countToken()) == .int(1))
        #expect(commit.after.position == .init(value: 1))
        #expect(await machine.current() == .snapshot(commit.after))
    }
}

import Foundation
import Testing
@testable import SwiftTLA

private enum LiveMachineTestError: Error {
    case evaluationUnavailable
}

@Suite("Live machine runtime")
struct LiveMachineRuntimeTests {
    private static let countToken = TLAStateProjection.Token(validating: "count")!

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

    private static func formalStateDictionary(_ projection: TLAStateProjection) -> [String: TLAValue] {
        Dictionary(uniqueKeysWithValues: projection.entries.map { ($0.token.description, $0.value) })
    }

    private static func transitionDriver(
        runtime: SpecRuntime,
        successors: @escaping @Sendable (TLAStateProjection, TLAActionInvocation) throws -> [TLAStateProjection],
        decodeState: @escaping @Sendable (TLAStateProjection) throws -> Void = { _ in }
    ) -> TLALiveMachineTransitionDriver {
        let formalActions = Dictionary(uniqueKeysWithValues: runtime.spec.actions.map { ($0.name, $0) })
        return TLALiveMachineTransitionDriver(
            successors: successors,
            availableInvocations: { projection in
                try runtime.availableInvocations(in: formalStateDictionary(projection))
            },
            validateInvocation: { invocation in
                guard let action = formalActions[invocation.name] else { return .unknownAction }
                guard action.bindings.count == invocation.arguments.count else { return .invalidArity }
                for (binding, argument) in zip(action.bindings, invocation.arguments)
                where !binding.values.contains(argument) {
                    return .actionArgumentOutOfDomain
                }
                return nil
            },
            decodeState: decodeState
        )
    }

    private static func realSuccessors(
        _ runtime: SpecRuntime
    ) -> @Sendable (TLAStateProjection, TLAActionInvocation) throws -> [TLAStateProjection] {
        { projection, invocation in
            try runtime.successors(invocation, from: formalStateDictionary(projection))
                .map { try TLAStateProjection(formalValues: $0) }
        }
    }

    private static func makeOwner(
        initialCount: Int = 0,
        driver: TLALiveMachineTransitionDriver? = nil
    ) throws -> TLALiveMachineOwner {
        let resolvedDriver: TLALiveMachineTransitionDriver
        if let driver {
            resolvedDriver = driver
        } else {
            resolvedDriver = transitionDriver(runtime: try SpecRuntime(spec: counterSpec()))
        }
        let initial = try TLAStateProjection(validating: [
            .init(token: countToken, value: .int(initialCount))
        ])
        return TLALiveMachineOwner.create(
            schema: counterSchema,
            initial: initial,
            driver: resolvedDriver
        )
    }

    private static func requireCurrentSnapshot(
        from machine: TLALiveMachine
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
        let invocation = TLAActionInvocation(name: "advance")

        #expect(await machine.current() == .unavailable(.endedByOwner))

        let outcome = await machine.execute(invocation, requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            invocation: invocation,
            reason: .runtimeUnavailable(.endedByOwner),
            current: before
        )))
        await owner.end()
        #expect(await machine.current() == .unavailable(.endedByOwner))
    }

    @Test("A request targeting another runtime identity is rejected and isolates")
    func foreignIdentityRequestRejectsWithoutCommit() async throws {
        let ownerA = try Self.makeOwner()
        let ownerB = try Self.makeOwner()
        let machineA = ownerA.handle
        let machineB = ownerB.handle
        let beforeA = try #require(await Self.requireCurrentSnapshot(from: machineA))
        let beforeB = try #require(await Self.requireCurrentSnapshot(from: machineB))
        let request = TLALiveActionRequest(
            requestID: UUID(),
            target: ownerB.identity,
            schemaIdentifier: Self.counterSchema.identifier,
            invocation: .init(name: "advance")
        )

        let outcome = await machineA.execute(request)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: request.requestID,
            invocation: request.invocation,
            reason: .identityMismatch,
            current: beforeA
        )))
        #expect(await machineA.current() == .snapshot(beforeA))
        #expect(await machineB.current() == .snapshot(beforeB))
    }

    @Test("A schema mismatch is rejected before acceptance and commits nothing")
    func schemaMismatchRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let request = TLALiveActionRequest(
            requestID: UUID(),
            target: machine.identity,
            schemaIdentifier: "unrelated-schema-v1",
            invocation: .init(name: "advance")
        )

        let outcome = await machine.execute(request)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: request.requestID,
            invocation: request.invocation,
            reason: .schemaMismatch,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("An unknown action is rejected before acceptance and commits nothing")
    func unknownActionRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()
        let invocation = TLAActionInvocation(name: "missing")

        let outcome = await machine.execute(invocation, requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            invocation: invocation,
            reason: .unknownAction,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("Wrong argument counts are rejected before acceptance and commit nothing")
    func invalidArityRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let firstID = UUID()
        let secondID = UUID()
        let stepInvocation = TLAActionInvocation(name: "step", arguments: [.int(1), .int(2)])
        let advanceInvocation = TLAActionInvocation(name: "advance", arguments: [.int(1)])

        let first = await machine.execute(stepInvocation, requestID: firstID)
        let second = await machine.execute(advanceInvocation, requestID: secondID)

        #expect(first == .rejected(TLALiveActionRejection(
            requestID: firstID,
            invocation: stepInvocation,
            reason: .invalidArity,
            current: before
        )))
        #expect(second == .rejected(TLALiveActionRejection(
            requestID: secondID,
            invocation: advanceInvocation,
            reason: .invalidArity,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("Arguments outside a declared domain are rejected before acceptance and commit nothing")
    func outOfDomainArgumentRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()
        let invocation = TLAActionInvocation(name: "step", arguments: [.int(9)])

        let outcome = await machine.execute(invocation, requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            invocation: invocation,
            reason: .actionArgumentOutOfDomain,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("A disabled action is rejected before acceptance and commits nothing")
    func disabledActionRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner(initialCount: 2)
        let machine = owner.handle
        _ = await machine.execute(.init(name: "advance"), requestID: UUID())
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        #expect(before.state.value(for: Self.countToken) == .int(3))
        #expect(before.position == .init(value: 1))
        let requestID = UUID()

        let outcome = await machine.execute(.init(name: "advance"), requestID: requestID)

        #expect(outcome == .rejected(TLALiveActionRejection(
            requestID: requestID,
            invocation: .init(name: "advance"),
            reason: .actionNotEnabled,
            current: before
        )))
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("An accepted evaluation failure leaves state and position unchanged")
    func evaluationFailureKeepsStateAndPosition() async throws {
        let runtime = try SpecRuntime(spec: Self.counterSpec())
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            runtime: runtime,
            successors: { _, _ in throw LiveMachineTestError.evaluationUnavailable }
        ))
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()

        let outcome = await machine.execute(.init(name: "advance"), requestID: requestID)

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
        let runtime = try SpecRuntime(spec: Self.counterSpec())
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            runtime: runtime,
            successors: Self.realSuccessors(runtime),
            decodeState: { _ in throw TLAStateProjectionDiagnostic.typeMismatch(
                path: "count",
                expected: "Int",
                actual: .int(0)
            ) }
        ))
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let requestID = UUID()

        let outcome = await machine.execute(.init(name: "advance"), requestID: requestID)

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
        let runtime = try SpecRuntime(spec: Self.counterSpec())
        let firstCandidate = try TLAStateProjection(validating: [
            .init(token: Self.countToken, value: .int(1))
        ])
        let secondCandidate = try TLAStateProjection(validating: [
            .init(token: Self.countToken, value: .int(2))
        ])
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            runtime: runtime,
            successors: { projection, invocation in
                if invocation.name == "step" {
                    return [firstCandidate, secondCandidate]
                }
                return try Self.realSuccessors(runtime)(projection, invocation)
            }
        ))
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))

        let ambiguousRequestID = UUID()
        let ambiguousOutcome = await machine.execute(.init(name: "step", arguments: [.int(1)]), requestID: ambiguousRequestID)

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
        let commitOutcome = await machine.execute(.init(name: "advance"), requestID: commitRequestID)

        guard case .committed(let commit) = commitOutcome else {
            Issue.record("Expected a committed transition, found \(commitOutcome)")
            return
        }
        #expect(commit.requestID == commitRequestID)
        #expect(commit.before == before)
        #expect(commit.after.state.value(for: Self.countToken) == .int(1))
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

        let outcome = await machine.execute(.init(name: "advance"), requestID: requestID)

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(commit.invocation == .init(name: "advance"))
        #expect(commit.before == before)
        #expect(commit.before.identity == owner.identity)
        #expect(commit.before.schemaIdentifier == Self.counterSchema.identifier)
        #expect(commit.before.position == .init(value: 0))
        #expect(commit.before.state.value(for: Self.countToken) == .int(0))
        #expect(commit.after.identity == owner.identity)
        #expect(commit.after.schemaIdentifier == Self.counterSchema.identifier)
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(commit.after.state.value(for: Self.countToken) == .int(1))
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Parameterized actions commit exactly once per accepted request")
    func parameterizedActionsCommitExactlyOncePerRequest() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle

        let first = await machine.execute(.init(name: "step", arguments: [.int(2)]), requestID: UUID())
        guard case .committed(let firstCommit) = first else {
            Issue.record("Expected a committed transition, found \(first)")
            return
        }
        #expect(firstCommit.before.state.value(for: Self.countToken) == .int(0))
        #expect(firstCommit.before.position == .init(value: 0))
        #expect(firstCommit.after.state.value(for: Self.countToken) == .int(2))
        #expect(firstCommit.after.position == .init(value: 1))
        #expect(firstCommit.after.position == firstCommit.before.position.next)

        let second = await machine.execute(.init(name: "step", arguments: [.int(1)]), requestID: UUID())
        guard case .committed(let secondCommit) = second else {
            Issue.record("Expected a committed transition, found \(second)")
            return
        }
        #expect(secondCommit.before == firstCommit.after)
        #expect(secondCommit.after.state.value(for: Self.countToken) == .int(3))
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

        let outcome = await first.execute(.init(name: "advance"), requestID: UUID())
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

        var secondary: TLALiveMachine? = owner.handle
        #expect(secondary?.identity == owner.identity)
        _ = await secondary?.execute(.init(name: "advance"), requestID: UUID())
        secondary = nil

        let current = try #require(await Self.requireCurrentSnapshot(from: primary))
        #expect(current.identity == owner.identity)
        #expect(current.schemaIdentifier == Self.counterSchema.identifier)
        #expect(current.state.value(for: Self.countToken) == .int(1))
        #expect(current.position == .init(value: 1))

        let outcome = await primary.execute(.init(name: "advance"), requestID: UUID())
        guard case .committed(let commit) = outcome else {
            Issue.record("Expected a committed transition, found \(outcome)")
            return
        }
        #expect(commit.after.state.value(for: Self.countToken) == .int(2))
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

        _ = await machineA.execute(.init(name: "advance"), requestID: UUID())
        _ = await machineA.execute(.init(name: "advance"), requestID: UUID())

        let currentA = try #require(await Self.requireCurrentSnapshot(from: machineA))
        let currentB = try #require(await Self.requireCurrentSnapshot(from: machineB))
        #expect(currentA.state.value(for: Self.countToken) == .int(2))
        #expect(currentA.position == .init(value: 2))
        #expect(currentA.identity == ownerA.identity)
        #expect(currentB.state.value(for: Self.countToken) == .int(0))
        #expect(currentB.position == .init(value: 0))
        #expect(currentB.identity == ownerB.identity)
    }

    @Test("Caller cancellation after acceptance still commits exactly once")
    func cancellationAfterAcceptanceStillCommits() async throws {
        let runtime = try SpecRuntime(spec: Self.counterSpec())
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            runtime: runtime,
            successors: { projection, invocation in
                signal.yield(())
                return try Self.realSuccessors(runtime)(projection, invocation)
            }
        ))
        let machine = owner.handle
        let requestID = UUID()
        var iterator = accepted.makeAsyncIterator()

        let task = Task { await machine.execute(.init(name: "advance"), requestID: requestID) }
        await iterator.next()
        task.cancel()
        let outcome = await task.value

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected the accepted request to commit, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(commit.before.state.value(for: Self.countToken) == .int(0))
        #expect(commit.before.position == .init(value: 0))
        #expect(commit.after.state.value(for: Self.countToken) == .int(1))
        #expect(commit.after.position == .init(value: 1))
        #expect(commit.after.position == commit.before.position.next)
        #expect(await machine.current() == .snapshot(commit.after))
    }

    @Test("Caller cancellation after acceptance still resolves to the accepted normal failure")
    func cancellationAfterAcceptanceStillFailsNormally() async throws {
        let runtime = try SpecRuntime(spec: Self.counterSpec())
        let (accepted, signal) = AsyncStream<Void>.makeStream()
        let owner = try Self.makeOwner(driver: Self.transitionDriver(
            runtime: runtime,
            successors: { _, _ in
                signal.yield(())
                throw LiveMachineTestError.evaluationUnavailable
            }
        ))
        let machine = owner.handle
        let requestID = UUID()
        var iterator = accepted.makeAsyncIterator()

        let task = Task { await machine.execute(.init(name: "advance"), requestID: requestID) }
        await iterator.next()
        task.cancel()
        let outcome = await task.value

        guard case .failed(let failure) = outcome else {
            Issue.record("Expected a normal failure, found \(outcome)")
            return
        }
        #expect(failure.requestID == requestID)
        #expect(failure.code == .evaluationFailed)
        #expect(failure.current.state.value(for: Self.countToken) == .int(0))
        #expect(failure.current.position == .init(value: 0))
        #expect(await machine.current() == .snapshot(failure.current))
    }

    @Test("Cancellation before the caller awaits cannot erase the accepted outcome")
    func cancellationBeforeAwaitStillCommits() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let requestID = UUID()

        let task = Task { await machine.execute(.init(name: "advance"), requestID: requestID) }
        task.cancel()
        let outcome = await task.value

        guard case .committed(let commit) = outcome else {
            Issue.record("Expected the request to commit, found \(outcome)")
            return
        }
        #expect(commit.requestID == requestID)
        #expect(commit.after.state.value(for: Self.countToken) == .int(1))
        #expect(commit.after.position == .init(value: 1))
        #expect(await machine.current() == .snapshot(commit.after))
    }
}

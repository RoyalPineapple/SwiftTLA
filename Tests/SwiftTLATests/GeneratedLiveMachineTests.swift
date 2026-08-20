import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct LiveMachineEquivalenceCounter {
    static var spec: TLASpec {
        TLASpec("LiveMachineEquivalenceCounter") {
            let count = Var<Int>("count")
            let delta = Expr<Int>(.variable("delta"))
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 3) }
            Action("step", parameters: [ActionParameter("delta", values: [1, 2])]) {
                count.becomes(count + delta).when(count + delta <= 3)
            }
        }
    }

    @TLAActor
    actor Actor {}
}

@TLAModel
private struct ForeignLiveMachineModel {
    static var spec: TLASpec {
        TLASpec("ForeignLiveMachineModel") {
            let level = Var<Int>("level")
            Variable(level, 0)
            Action("raise") { level.becomes(level + 1).when(level < 1) }
        }
    }

    @TLAActor
    actor Actor {}
}

@Suite("Generated live machine")
struct GeneratedLiveMachineTests {
    private static func makeOwner() throws -> TLALiveMachineOwner {
        try TLALiveMachineOwner.create(for: LiveMachineEquivalenceCounter.self)
    }

    private static func requireCurrentSnapshot(
        from machine: TLALiveMachine
    ) async -> TLALiveMachineSnapshot? {
        guard case .snapshot(let snapshot) = await machine.current() else { return nil }
        return snapshot
    }

    private static func inspectTypeUnknown(
        _ machine: TLALiveMachine
    ) async -> (
        identity: TLALiveMachineIdentity,
        schemaIdentifier: String,
        schema: MachineSchema,
        snapshot: TLALiveMachineSnapshot
    )? {
        guard case .snapshot(let snapshot) = await machine.current() else { return nil }
        return (machine.identity, machine.schemaIdentifier, machine.schema, snapshot)
    }

    @Test("Typed and generic executions of one enabled action commit the same state and position")
    func typedAndGenericAdvanceCommitTheSameStateAndPosition() async throws {
        let typedOwner = try Self.makeOwner()
        let genericOwner = try Self.makeOwner()
        let typedLive = try LiveMachineEquivalenceCounter.Live(handle: typedOwner.handle)
        let genericLive = try LiveMachineEquivalenceCounter.Live(handle: genericOwner.handle)
        let advance = LiveMachineEquivalenceCounter.ActionLabel.advance

        let typedOutcome = await typedLive.execute(advance)
        let genericOutcome = await genericLive.execute(advance.toInvocation())

        guard case .committed(let typedCommit) = typedOutcome else {
            Issue.record("Expected a typed committed transition, found \(typedOutcome)")
            return
        }
        guard case .committed(let genericCommit) = genericOutcome else {
            Issue.record("Expected a generic committed transition, found \(genericOutcome)")
            return
        }

        #expect(typedCommit.action == advance)
        #expect(typedCommit.action.toInvocation() == genericCommit.invocation)
        #expect(typedCommit.before == LiveMachineEquivalenceCounter.State(count: 0))
        #expect(typedCommit.after == LiveMachineEquivalenceCounter.State(count: 1))
        #expect(try LiveMachineEquivalenceCounter.State(projection: genericCommit.before.state) == typedCommit.before)
        #expect(try LiveMachineEquivalenceCounter.State(projection: genericCommit.after.state) == typedCommit.after)
        #expect(genericCommit.after.position == genericCommit.before.position.next)
        #expect(genericCommit.after.position == TLALiveMachinePosition(value: 1))

        guard case .snapshot(let typedCurrent) = await typedLive.current() else {
            Issue.record("Expected a typed current snapshot, found unavailability")
            return
        }
        let genericCurrent = try #require(await Self.requireCurrentSnapshot(from: genericOwner.handle))
        #expect(typedCurrent.identity == typedOwner.identity)
        #expect(typedCurrent.state == typedCommit.after)
        #expect(typedCurrent.position == genericCommit.after.position)
        #expect(genericCurrent.identity == genericOwner.identity)
        #expect(genericCurrent.position == typedCurrent.position)
        #expect(genericCurrent.schemaIdentifier == typedLive.schema.identifier)
        #expect(try LiveMachineEquivalenceCounter.State(projection: genericCurrent.state) == typedCurrent.state)
    }

    @Test("Typed and generic parameterized actions commit the same state and position")
    func typedAndGenericStepCommitTheSameStateAndPosition() async throws {
        let typedOwner = try Self.makeOwner()
        let genericOwner = try Self.makeOwner()
        let typedLive = try LiveMachineEquivalenceCounter.Live(handle: typedOwner.handle)
        let genericLive = try LiveMachineEquivalenceCounter.Live(handle: genericOwner.handle)
        let stepLabel = LiveMachineEquivalenceCounter.ActionLabel.step(delta: 2)
        let stepInvocation = TLAActionInvocation(name: "step", arguments: [.int(2)])

        #expect(stepLabel.toInvocation() == stepInvocation)

        let typedOutcome = await typedLive.execute(stepLabel)
        let genericOutcome = await genericLive.execute(stepInvocation)

        guard case .committed(let typedCommit) = typedOutcome else {
            Issue.record("Expected a typed committed transition, found \(typedOutcome)")
            return
        }
        guard case .committed(let genericCommit) = genericOutcome else {
            Issue.record("Expected a generic committed transition, found \(genericOutcome)")
            return
        }

        #expect(typedCommit.action == stepLabel)
        #expect(typedCommit.action.toInvocation() == genericCommit.invocation)
        #expect(typedCommit.before == LiveMachineEquivalenceCounter.State(count: 0))
        #expect(typedCommit.after == LiveMachineEquivalenceCounter.State(count: 2))
        #expect(try LiveMachineEquivalenceCounter.State(projection: genericCommit.after.state) == typedCommit.after)
        #expect(genericCommit.after.position == TLALiveMachinePosition(value: 1))

        guard case .snapshot(let typedCurrent) = await typedLive.current() else {
            Issue.record("Expected a typed current snapshot, found unavailability")
            return
        }
        let genericCurrent = try #require(await Self.requireCurrentSnapshot(from: genericOwner.handle))
        #expect(typedCurrent.position == genericCurrent.position)
        #expect(typedCurrent.state == typedCommit.after)
        #expect(try LiveMachineEquivalenceCounter.State(projection: genericCurrent.state) == typedCommit.after)
    }

    @Test("The typed facade and the generated machine route one action through the same pipeline")
    func typedFacadeAndGeneratedMachineRouteTheSamePipeline() async throws {
        let facadeOwner = try Self.makeOwner()
        let machineOwner = try Self.makeOwner()
        let facade = try LiveMachineEquivalenceCounter.Live(handle: facadeOwner.handle)
        let machine = try GeneratedLiveMachine<LiveMachineEquivalenceCounter>(handle: machineOwner.handle)
        let advance = LiveMachineEquivalenceCounter.ActionLabel.advance
        let requestID = UUID()

        let facadeOutcome = await facade.execute(advance, requestID: requestID)
        let machineOutcome = await machine.execute(advance, requestID: requestID)

        guard case .committed(let facadeCommit) = facadeOutcome else {
            Issue.record("Expected a committed facade transition, found \(facadeOutcome)")
            return
        }
        guard case .committed(let machineCommit) = machineOutcome else {
            Issue.record("Expected a committed machine transition, found \(machineOutcome)")
            return
        }

        #expect(machineCommit.requestID == requestID)
        #expect(machineCommit.invocation == advance.toInvocation())
        #expect(facadeCommit.action == advance)
        #expect(try LiveMachineEquivalenceCounter.State(projection: machineCommit.before.state) == facadeCommit.before)
        #expect(try LiveMachineEquivalenceCounter.State(projection: machineCommit.after.state) == facadeCommit.after)
        #expect(machineCommit.after.position == TLALiveMachinePosition(value: 1))

        guard case .snapshot(let facadeCurrent) = await facade.current() else {
            Issue.record("Expected a current facade snapshot, found unavailability")
            return
        }
        #expect(facadeCurrent.position == machineCommit.after.position)
        #expect(facadeCurrent.state == facadeCommit.after)
    }

    @Test("A typed action that is not enabled in the current state rejects without commit")
    func typedDisabledActionRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let live = try LiveMachineEquivalenceCounter.Live(handle: owner.handle)

        for _ in 0..<3 {
            guard case .committed = await live.execute(.advance) else {
                Issue.record("Expected the advance request to commit")
                return
            }
        }
        guard case .snapshot(let before) = await live.current() else {
            Issue.record("Expected a current snapshot, found unavailability")
            return
        }
        #expect(before.state == LiveMachineEquivalenceCounter.State(count: 3))
        #expect(before.position == TLALiveMachinePosition(value: 3))

        let requestID = UUID()
        let outcome = await live.execute(.advance, requestID: requestID)

        guard case .rejected(let rejection) = outcome else {
            Issue.record("Expected a typed rejection, found \(outcome)")
            return
        }
        #expect(rejection.requestID == requestID)
        #expect(rejection.invocation == .init(name: "advance"))
        #expect(rejection.reason == .actionNotEnabled)
        #expect(rejection.current.position == before.position)
        #expect(try LiveMachineEquivalenceCounter.State(projection: rejection.current.state) == before.state)

        guard case .snapshot(let after) = await live.current() else {
            Issue.record("Expected a current snapshot, found unavailability")
            return
        }
        #expect(after == before)
        let raw = try #require(await Self.requireCurrentSnapshot(from: owner.handle))
        #expect(raw.position == before.position)
        #expect(try LiveMachineEquivalenceCounter.State(projection: raw.state) == before.state)
    }

    @Test("A generic unknown action rejects explicitly without commit")
    func genericUnknownActionRejectsWithoutCommit() async throws {
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

    @Test("Generic invocations with an invalid argument count reject without commit")
    func genericInvalidArityRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let missingArgument = TLAActionInvocation(name: "step")
        let extraArgument = TLAActionInvocation(name: "advance", arguments: [.int(1)])

        let firstOutcome = await machine.execute(missingArgument, requestID: UUID())
        let secondOutcome = await machine.execute(extraArgument, requestID: UUID())

        guard case .rejected(let first) = firstOutcome else {
            Issue.record("Expected an arity rejection, found \(firstOutcome)")
            return
        }
        guard case .rejected(let second) = secondOutcome else {
            Issue.record("Expected an arity rejection, found \(secondOutcome)")
            return
        }
        #expect(first.reason == .invalidArity)
        #expect(first.invocation == missingArgument)
        #expect(second.reason == .invalidArity)
        #expect(second.invocation == extraArgument)
        #expect(await machine.current() == .snapshot(before))
    }

    @Test("A generic invocation with an out-of-domain argument rejects without commit")
    func genericOutOfDomainArgumentRejectsWithoutCommit() async throws {
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

    @Test("A request declaring an incompatible schema identifier rejects without commit")
    func schemaMismatchRequestRejectsWithoutCommit() async throws {
        let owner = try Self.makeOwner()
        let machine = owner.handle
        let before = try #require(await Self.requireCurrentSnapshot(from: machine))
        let request = TLALiveActionRequest(
            requestID: UUID(),
            target: machine.identity,
            schemaIdentifier: "another-generated-schema-v1",
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

    @Test("Binding a handle with an incompatible generated schema fails explicitly")
    func incompatibleHandleBindingFailsExplicitly() async throws {
        let counterOwner = try Self.makeOwner()
        let foreignOwner = try TLALiveMachineOwner.create(for: ForeignLiveMachineModel.self)

        do {
            _ = try GeneratedLiveMachine<LiveMachineEquivalenceCounter>(handle: foreignOwner.handle)
            Issue.record("Expected the incompatible generated machine binding to fail")
        } catch let diagnostic as GeneratedLiveMachineDiagnostic {
            #expect(diagnostic.code == .handleSchemaMismatch)
            #expect(diagnostic.expected == LiveMachineEquivalenceCounter.machineSchema.identifier)
            #expect(diagnostic.actual == ForeignLiveMachineModel.machineSchema.identifier)
        }

        do {
            _ = try LiveMachineEquivalenceCounter.Live(handle: foreignOwner.handle)
            Issue.record("Expected the incompatible typed facade binding to fail")
        } catch let diagnostic as GeneratedLiveMachineDiagnostic {
            #expect(diagnostic.code == .handleSchemaMismatch)
        }

        #expect(foreignOwner.identity != counterOwner.identity)
        let foreignCurrent = try #require(await Self.requireCurrentSnapshot(from: foreignOwner.handle))
        #expect(foreignCurrent.position == TLALiveMachinePosition(value: 0))
        #expect(try ForeignLiveMachineModel.State(projection: foreignCurrent.state) == ForeignLiveMachineModel.State(level: 0))
    }

    @Test("The generated binding exposes schema and identity to type-unknown consumers")
    func generatedBindingExposesSchemaAndIdentity() async throws {
        let owner = try Self.makeOwner()
        let live = try LiveMachineEquivalenceCounter.Live(handle: owner.handle)
        let metadata = LiveMachineEquivalenceCounter.generatedMachineMetadata

        #expect(live.identity == owner.identity)
        #expect(live.handle.identity == owner.identity)
        #expect(live.schema == LiveMachineEquivalenceCounter.machineSchema)
        #expect(live.schema.identifier == metadata.schemaIdentifier)
        #expect(live.handle.schemaIdentifier == live.schema.identifier)
        #expect(live.schema.model.name == "LiveMachineEquivalenceCounter")
        #expect(live.schema.state.map(\.id) == ["count"])
        #expect(live.schema.state.first?.value == .integer)
        #expect(live.schema.state.first?.swiftType == "Int")
        #expect(live.schema.actions.map(\.id) == ["advance", "step"])
        #expect(live.schema.actions.first?.parameters == [MachineSchema.Field]())
        #expect(live.schema.actions.last?.parameters.map(\.id) == ["delta"])
        #expect(live.schema.actions.last?.parameters.first?.value == .integer)

        let inspected = try #require(await Self.inspectTypeUnknown(live.handle))
        #expect(inspected.identity == live.identity)
        #expect(inspected.schemaIdentifier == inspected.schema.identifier)
        #expect(inspected.schema == live.schema)
        #expect(inspected.snapshot.identity == inspected.identity)
        #expect(inspected.snapshot.schemaIdentifier == inspected.schemaIdentifier)
        #expect(inspected.snapshot.position == TLALiveMachinePosition(value: 0))
        #expect(try LiveMachineEquivalenceCounter.State(projection: inspected.snapshot.state)
            == LiveMachineEquivalenceCounter.State(count: 0))
    }
}

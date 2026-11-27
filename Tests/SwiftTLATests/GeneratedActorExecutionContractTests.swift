import Testing
import SwiftTLA

struct GeneratedActorExecutionContractTests {
    @Test("actor matches the generated machine for a typed schedule")
    func actorMatchesGeneratedMachineForTypedSchedule() async throws {
        var machine = try ParameterizedActorModel.makeMachine()
        let actor = try ParameterizedActorModel.Actor()
        let schedule: [ParameterizedActorModel.Action] = [
            .pass(from: 1, to: 2, round: 1),
            .pass(from: 2, to: 1, round: 2),
            .pass(from: 1, to: 2, round: 3)
        ]

        #expect(await actor.state == machine.state)

        for action in schedule {
            try machine.send(action)
            try await actor.send(action)
            #expect(await actor.state == machine.state)
        }
    }

    @Test("disabled typed action leaves actor state unchanged")
    func disabledTypedActionLeavesActorStateUnchanged() async throws {
        let actor = try ParameterizedActorModel.Actor()
        let unavailable = ParameterizedActorModel.Action.pass(from: 2, to: 1, round: 1)
        let before = await actor.state
        await #expect(throws: GeneratedMachineError.self) {
            try await actor.send(unavailable)
        }

        #expect(await actor.state == before)
    }

    @Test("concurrent duplicate actions commit once")
    func concurrentDuplicateActionsCommitOnce() async throws {
        let actor = try ParameterizedActorModel.Actor()
        let action = ParameterizedActorModel.Action.pass(from: 1, to: 2, round: 1)

        async let first = submit(actor, action: action)
        async let second = submit(actor, action: action)
        let submissions = try await [first, second]

        var machine = try ParameterizedActorModel.makeMachine()
        try machine.send(action)
        #expect(submissions.filter { $0 == .applied }.count == 1)
        #expect(submissions.filter { $0 == .disabled }.count == 1)
        #expect(await actor.state == machine.state)
    }

    private func submit(
        _ actor: ParameterizedActorModel.Actor,
        action: ParameterizedActorModel.Action
    ) async throws -> Submission {
        do {
            try await actor.send(action)
            return .applied
        } catch GeneratedMachineError.noMatchingSuccessor {
            return .disabled
        }
    }

    private enum Submission: Sendable { case applied, disabled }
}

import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ParameterizedActorModel {
    static var spec: TLASpec {
        TLASpec("ParameterizedActorModel") {
            let leader = Var<Int>("leader")
            let turn = Var<Int>("turn")
            Variable(leader, 1)
            Variable(turn, 0)
            SwiftTLA.Action("pass", parameters: [
                ActionParameter("from", values: [1, 2]),
                ActionParameter("to", values: [1, 2]),
                ActionParameter("round", values: [1, 2, 3])
            ]) {
                let from = Expr<Int>(.variable("from"))
                let to = Expr<Int>(.variable("to"))
                let round = Expr<Int>(.variable("round"))
                leader == from
                    && to != from
                    && turn + 1 == round
                    && leader.becomes(to)
                    && turn.becomes(round)
            }
        }
    }

}

struct GeneratedActorExecutionContractTests {
    @Test("actor matches the generated machine for a typed schedule")
    func actorMatchesValueMachineForTypedSchedule() async throws {
        var machine = try ParameterizedActorModel.makeMachine()
        let actor = try ParameterizedActorModel.Actor()
        let schedule: [ParameterizedActorModel.Action] = [
            .pass(from: 1, to: 2, round: 1),
            .pass(from: 2, to: 1, round: 2),
            .pass(from: 1, to: 2, round: 3)
        ]

        #expect(await actor.state == machine.state)

        for action in schedule {
            let expected = try machine.send(action)
            let actual = try await actor.send(action)

            #expect(actual.action == expected.action)
            #expect(actual.before == expected.before)
            #expect(actual.after == expected.after)
            #expect(await actor.state == expected.after)
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
        let submissions = await [first, second]

        var machine = try ParameterizedActorModel.makeMachine()
        let expected = try machine.send(action)
        let committedTransitions = submissions.compactMap(\.transition)
        let rejected = submissions.filter(\.isUnexpected)

        #expect(committedTransitions.count == 1)
        #expect(rejected.count == 1)
        #expect(committedTransitions[0].action == expected.action)
        #expect(committedTransitions[0].before == expected.before)
        #expect(committedTransitions[0].after == expected.after)
        #expect(await actor.state == expected.after)
    }

    private func submit(
        _ actor: ParameterizedActorModel.Actor,
        action: ParameterizedActorModel.Action
    ) async -> Submission {
        do {
            let transition = try await actor.send(action)
            return .applied(transition)
        } catch {
            return .unexpected
        }
    }

    private enum Submission: Sendable {
        case applied(ParameterizedActorModel.Transition)
        case unexpected

        var transition: ParameterizedActorModel.Transition? {
            guard case .applied(let transition) = self else { return nil }
            return transition
        }

        var isUnexpected: Bool {
            if case .unexpected = self { return true }
            return false
        }
    }
}

import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DuckDuckLeaderCanonical {
    static var spec: TLASpec {
        TLASpec("DuckDuckLeaderCanonical") {
            let leader = Var<Int>("leader")
            let turn = Var<Int>("turn")
            Variable(leader, 1)
            Variable(turn, 0)
            Action("pass", parameters: [
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

    @TLAActor
    actor Actor {}
}

struct GeneratedActorExecutionContractTests {
    @Test("actor preserves canonical arbitrary-length evidence")
    func actorMatchesCanonicalSchedule() async throws {
        var canonical = try DuckDuckLeaderCanonical.makeMachine()
        let actor = DuckDuckLeaderCanonical.Actor(live: try DuckDuckLeaderCanonical.makeLive())
        let schedule: [DuckDuckLeaderCanonical.Action] = [
            .pass(from: 1, to: 2, round: 1),
            .pass(from: 2, to: 1, round: 2),
            .pass(from: 1, to: 2, round: 3)
        ]

        #expect(try await state(of: actor) == canonical.state)

        for label in schedule {
            let expected = try canonical.send(label)
            let actual = try committed(try await actor.send(label))

            #expect(actual.action == label)
            #expect(actual.action == expected.action)
            #expect(actual.before.leader == expected.before.leader)
            #expect(actual.before.turn == expected.before.turn)
            #expect(actual.after.leader == expected.after.leader)
            #expect(actual.after.turn == expected.after.turn)
            #expect(try await state(of: actor).leader == expected.after.leader)
            #expect(try await state(of: actor).turn == expected.after.turn)
        }
    }

    @Test("actor rejects unavailable invocations without mutation")
    func unavailableActionPreservesActorSnapshot() async throws {
        let actor = DuckDuckLeaderCanonical.Actor(live: try DuckDuckLeaderCanonical.makeLive())
        let unavailable = DuckDuckLeaderCanonical.Actor.Action.pass(from: 2, to: 1, round: 1)
        let before = try await state(of: actor)
        let outcome = try await actor.send(unavailable)
        if case .rejected = outcome {
        } else {
            Issue.record("Expected unavailable actor action")
        }

        #expect(try await state(of: actor) == before)
    }

    @Test("actor serializes concurrent duplicate submissions")
    func concurrentSubmissionsMatchActualCanonicalEvidence() async throws {
        let actor = DuckDuckLeaderCanonical.Actor(live: try DuckDuckLeaderCanonical.makeLive())
        let label = DuckDuckLeaderCanonical.Actor.Action.pass(from: 1, to: 2, round: 1)

        async let first = submit(actor, label: label)
        async let second = submit(actor, label: label)
        let submissions = await [first, second]

        var canonical = try DuckDuckLeaderCanonical.makeMachine()
        let expected = try canonical.send(.pass(from: 1, to: 2, round: 1))
        let successful = submissions.compactMap(\.evidence)
        let rejected = submissions.filter(\.isRejected)

        #expect(successful.count == 1)
        #expect(rejected.count == 1)
        #expect(successful[0].action == expected.action)
        #expect(successful[0].before.leader == expected.before.leader)
        #expect(successful[0].before.turn == expected.before.turn)
        #expect(successful[0].after.leader == expected.after.leader)
        #expect(successful[0].after.turn == expected.after.turn)
        #expect(try await state(of: actor).leader == expected.after.leader)
        #expect(try await state(of: actor).turn == expected.after.turn)
    }

    private func submit(
        _ actor: DuckDuckLeaderCanonical.Actor,
        label: DuckDuckLeaderCanonical.Actor.Action
    ) async -> Submission {
        do {
            switch try await actor.send(label) {
            case .committed(let evidence):
                return .applied(.init(
                    action: evidence.action,
                    before: evidence.before,
                    after: evidence.after
                ))
            case .rejected:
                return .rejected
            case .failed:
                return .unexpected
            }
        } catch {
            return .unexpected
        }
    }

    private func state(of actor: DuckDuckLeaderCanonical.Actor) async throws -> DuckDuckLeaderCanonical.State {
        switch try await actor.current() {
        case .snapshot(let snapshot): return snapshot.state
        case .unavailable(let reason): throw GeneratedMachineError.liveMachineUnavailable(String(describing: reason))
        }
    }

    private func committed(
        _ outcome: DuckDuckLeaderCanonical.Actor.Outcome
    ) throws -> DuckDuckLeaderCanonical.Transition {
        switch outcome {
        case .committed(let result): return result
        case .rejected, .failed: throw GeneratedMachineError.noMatchingSuccessor
        }
    }

    private enum Submission: Sendable {
        case applied(Evidence)
        case rejected
        case unexpected

        var evidence: Evidence? {
            guard case .applied(let evidence) = self else { return nil }
            return evidence
        }

        var isRejected: Bool {
            if case .rejected = self { return true }
            return false
        }
    }

    private struct Evidence: Sendable {
        let action: DuckDuckLeaderCanonical.Actor.Action
        let before: DuckDuckLeaderCanonical.Actor.State
        let after: DuckDuckLeaderCanonical.Actor.State
    }
}

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
        var canonical = DuckDuckLeaderCanonical()
        let actor = DuckDuckLeaderCanonical.Actor()
        let schedule: [DuckDuckLeaderCanonical.ActionLabel] = [
            .pass(from: 1, to: 2, round: 1),
            .pass(from: 2, to: 1, round: 2),
            .pass(from: 1, to: 2, round: 3)
        ]

        #expect(await actor.tlaSnapshot() == canonical.tlaSnapshot())

        for label in schedule {
            let expected = try canonical.apply(label)
            let actual = try await actor.apply(.pass(from: label.from, to: label.to, round: label.round))

            #expect(actual.action == label)
            #expect(actual.action == expected.action)
            #expect(actual.before.leader == expected.before.leader)
            #expect(actual.before.turn == expected.before.turn)
            #expect(actual.after.leader == expected.after.leader)
            #expect(actual.after.turn == expected.after.turn)
            #expect(await actor.state.leader == expected.after.leader)
            #expect(await actor.state.turn == expected.after.turn)
        }
    }

    @Test("actor rejects unavailable invocations without mutation")
    func unavailableActionPreservesActorSnapshot() async throws {
        let actor = DuckDuckLeaderCanonical.Actor()
        let unavailable = DuckDuckLeaderCanonical.Actor.ActionLabel.pass(from: 2, to: 1, round: 1)
        let before = await actor.tlaSnapshot()

        do {
            _ = try await actor.apply(unavailable)
            Issue.record("Expected unavailable actor action")
        } catch is GeneratedMachineError {
        }

        #expect(await actor.tlaSnapshot() == before)
    }

    @Test("actor serializes concurrent duplicate submissions")
    func concurrentSubmissionsMatchActualCanonicalEvidence() async throws {
        let actor = DuckDuckLeaderCanonical.Actor()
        let label = DuckDuckLeaderCanonical.Actor.ActionLabel.pass(from: 1, to: 2, round: 1)

        async let first = submit(actor, label: label)
        async let second = submit(actor, label: label)
        let submissions = await [first, second]

        var canonical = DuckDuckLeaderCanonical()
        let expected = try canonical.apply(.pass(from: 1, to: 2, round: 1))
        let successful = submissions.compactMap(\.evidence)
        let rejected = submissions.filter(\.isRejected)

        #expect(successful.count == 1)
        #expect(rejected.count == 1)
        #expect(successful[0].action == expected.action)
        #expect(successful[0].before.leader == expected.before.leader)
        #expect(successful[0].before.turn == expected.before.turn)
        #expect(successful[0].after.leader == expected.after.leader)
        #expect(successful[0].after.turn == expected.after.turn)
        #expect(await actor.state.leader == expected.after.leader)
        #expect(await actor.state.turn == expected.after.turn)
    }

    private func submit(
        _ actor: DuckDuckLeaderCanonical.Actor,
        label: DuckDuckLeaderCanonical.Actor.ActionLabel
    ) async -> Submission {
        do {
            let evidence = try await actor.apply(label)
            return .applied(.init(
                action: evidence.action,
                before: evidence.before,
                after: evidence.after
            ))
        } catch is GeneratedMachineError {
            return .rejected
        } catch {
            return .unexpected(String(describing: error))
        }
    }

    private enum Submission: Sendable {
        case applied(Evidence)
        case rejected
        case unexpected(String)

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
        let action: DuckDuckLeaderCanonical.Actor.ActionLabel
        let before: DuckDuckLeaderCanonical.Actor.State
        let after: DuckDuckLeaderCanonical.Actor.State
    }
}

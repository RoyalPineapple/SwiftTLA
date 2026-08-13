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
}

@TLAActor
actor DuckDuckLeaderActor {
    static var spec: TLASpec {
        TLASpec("DuckDuckLeaderActor") {
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
}

struct DuckDuckLeaderAdapterTests {
    @Test("Duck Duck Leader actor preserves canonical arbitrary-length evidence")
    func actorMatchesCanonicalSchedule() async throws {
        var canonical = DuckDuckLeaderCanonical()
        let actor = DuckDuckLeaderActor()
        let schedule = [
            TLAActionInvocation(name: "pass", arguments: [.int(1), .int(2), .int(1)]),
            TLAActionInvocation(name: "pass", arguments: [.int(2), .int(1), .int(2)]),
            TLAActionInvocation(name: "pass", arguments: [.int(1), .int(2), .int(3)])
        ]

        #expect(await actor.tlaSnapshot() == canonical.tlaSnapshot())

        for invocation in schedule {
            let canonicalLabel = try #require(DuckDuckLeaderCanonical.ActionLabel(invocation: invocation))
            let actorLabel = try #require(DuckDuckLeaderActor.ActionLabel(invocation: invocation))
            let expected = try canonical.apply(canonicalLabel)
            let actual = try await actor.apply(actorLabel)

            #expect(actual.label.toInvocation() == invocation)
            #expect(actual.label.toInvocation() == expected.label.toInvocation())
            #expect(actual.before == expected.before)
            #expect(actual.after == expected.after)
            let leader = TLAStateProjection.Token(validating: "leader")!
            let turn = TLAStateProjection.Token(validating: "turn")!
            #expect(await actor.tlaSnapshot().projection?.value(for: leader) == expected.after["leader"])
            #expect(await actor.tlaSnapshot().projection?.value(for: turn) == expected.after["turn"])
        }
    }

    @Test("Duck Duck Leader actor rejects unavailable invocations without mutation")
    func unavailableActionPreservesActorSnapshot() async throws {
        let actor = DuckDuckLeaderActor()
        let unavailable = TLAActionInvocation(name: "pass", arguments: [.int(2), .int(1), .int(1)])
        let before = await actor.tlaSnapshot()

        do {
            _ = try await actor.apply(try #require(DuckDuckLeaderActor.ActionLabel(invocation: unavailable)))
            Issue.record("Expected unavailable Duck Duck Leader action")
        } catch let GeneratedMachineError.runtime(.actionNotEnabled(invocation, available)) {
            #expect(invocation == unavailable)
            #expect(available.contains(unavailable) == false)
        }

        #expect(await actor.tlaSnapshot() == before)
    }

    @Test("Duck Duck Leader actor serializes concurrent duplicate submissions")
    func concurrentSubmissionsMatchActualCanonicalEvidence() async throws {
        let actor = DuckDuckLeaderActor()
        let invocation = TLAActionInvocation(name: "pass", arguments: [.int(1), .int(2), .int(1)])

        async let first = submit(actor, invocation: invocation)
        async let second = submit(actor, invocation: invocation)
        let submissions = await [first, second]

        var canonical = DuckDuckLeaderCanonical()
        let label = try #require(DuckDuckLeaderCanonical.ActionLabel(invocation: invocation))
        let expected = try canonical.apply(label)
        let expectedAvailable = try canonical.availableActions().map { $0.toInvocation() }
        let successful = submissions.compactMap(\.evidence)
        let rejected = submissions.compactMap(\.rejection)

        #expect(successful.count == 1)
        #expect(rejected.count == 1)
        #expect(successful[0].invocation == expected.label.toInvocation())
        #expect(successful[0].before == expected.before)
        #expect(successful[0].after == expected.after)
        #expect(rejected[0].invocation == invocation)
        #expect(rejected[0].available == expectedAvailable)
        let leader = TLAStateProjection.Token(validating: "leader")!
        let turn = TLAStateProjection.Token(validating: "turn")!
        #expect(await actor.tlaSnapshot().projection?.value(for: leader) == expected.after["leader"])
        #expect(await actor.tlaSnapshot().projection?.value(for: turn) == expected.after["turn"])
    }

    private func submit(
        _ actor: DuckDuckLeaderActor,
        invocation: TLAActionInvocation
    ) async -> Submission {
        do {
            let label = try #require(DuckDuckLeaderActor.ActionLabel(invocation: invocation))
            let evidence = try await actor.apply(label)
            return .applied(.init(
                invocation: evidence.label.toInvocation(),
                before: evidence.before,
                after: evidence.after
            ))
        } catch let GeneratedMachineError.runtime(.actionNotEnabled(rejected, available)) {
            return .rejected(.init(invocation: rejected, available: available))
        } catch {
            return .unexpected(String(describing: error))
        }
    }

    private enum Submission: Sendable {
        case applied(Evidence)
        case rejected(Rejection)
        case unexpected(String)

        var evidence: Evidence? {
            guard case .applied(let evidence) = self else { return nil }
            return evidence
        }

        var rejection: Rejection? {
            guard case .rejected(let rejection) = self else { return nil }
            return rejection
        }
    }

    private struct Evidence: Sendable {
        let invocation: TLAActionInvocation
        let before: [String: TLAValue]
        let after: [String: TLAValue]
    }

    private struct Rejection: Sendable {
        let invocation: TLAActionInvocation
        let available: [TLAActionInvocation]
    }
}

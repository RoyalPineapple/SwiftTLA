// Replicas collect promises and accept a value once a quorum has voted for it.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SimplifiedFastPaxos/Paxos.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SimplifiedPaxosModel: Sendable {
    package enum Replica: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2, r3, r4
        package static let defaultValue = Self.r1
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, v3, none, any
        package static let defaultValue = Self.none
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct Prepare: Hashable, Sendable {
        package let type: String
        package let ballot: Int
    }
    package struct Promise: Hashable, Sendable {
        package let type: String
        package let ballot: Int
        package let acceptor: Replica
        package let maxVBallot: Int
        package let maxValue: Value
    }
    package struct Proposal: Hashable, Sendable {
        package let type: String
        package let ballot: Int
        package let value: Value
    }
    package struct Vote: Hashable, Sendable {
        package let type: String
        package let ballot: Int
        package let acceptor: Replica
        package let value: Value
    }
    package typealias PhaseOne = OneOf<Prepare, Promise>
    package typealias PhaseTwo = OneOf<Proposal, Vote>
    package typealias Message = OneOf<PhaseOne, PhaseTwo>
    private enum Step: String, CaseIterable {
        case prepare = "PaxosPrepare", promise = "PaxosPromise", accept = "PaxosAccept"
        case accepted = "PaxosAccepted", decide = "PaxosDecide"
    }

    package static var spec: TLASpec {
        #spec("Paxos") { scope in
            Extends(.integers, .finiteSets)
            let replicas = scope.parameter(as: Set<Replica>.self, in: Set<Set<Replica>>([Set([.r1, .r2, .r3, .r4])]))
            let values = scope.parameter(as: Set<Value>.self, in: Set<Set<Value>>([Set([.v1, .v2, .v3])]))
            let ballots = IntRange(0, through: 2)
            let quorums = scope.parameter(as: Set<Set<Replica>>.self, in: Set<Set<Set<Replica>>>([
                Set<Set<Replica>>([[Replica.r1, Replica.r2, Replica.r3], [Replica.r1, Replica.r2, Replica.r4], [Replica.r1, Replica.r3, Replica.r4], [Replica.r2, Replica.r3, Replica.r4]])
            ]))
            let messages = scope.sharedVar(initial: Set<Message>())
            let decision = scope.sharedVar(initial: Value.none)
            let maxBallot = scope.sharedVar(initial: Dictionary<Replica, Int>.mapping(over: replicas) { _ in 0 })
            let maxVBallot = scope.sharedVar(initial: Dictionary<Replica, Int>.mapping(over: replicas) { _ in 0 })
            let maxValue = scope.sharedVar(initial: Dictionary<Replica, Value>.mapping(over: replicas) { _ in Value.none })

            Assume(!values.contains(Value.any) && !values.contains(Value.none))
            Assume(quorums.allSatisfy { q in q.isSubset(of: replicas) && replicas.count / 2 < q.count })
            Assume(quorums.allSatisfy { q in quorums.allSatisfy { r in !q.intersection(r).isEmpty } })

            let prepares = messages.filter { m in m.recordFields == Set<String>(["type", "ballot"]) }.mapping { m in m.assuming(Prepare.self) }
            let promises = messages.filter { m in m.recordFields == Set<String>(["type", "ballot", "acceptor", "maxVBallot", "maxValue"]) }.mapping { m in m.assuming(Promise.self) }
            let proposals = messages.filter { m in m.recordFields == Set<String>(["type", "ballot", "value"]) }.mapping { m in m.assuming(Proposal.self) }
            let votes = messages.filter { m in m.recordFields == Set<String>(["type", "ballot", "acceptor", "value"]) }.mapping { m in m.assuming(Vote.self) }

            Do(Step.prepare) {
                With(IntRange(1, through: 2)) { ballot in
                    messages.insert(Message.first(PhaseOne.first(Prepare.expression(type: "P1a", ballot: ballot))))
                }
            }
            Do(Step.promise) {
                With(replicas, ballots) { acceptor, ballot in
                    When(messages.contains(Message.first(PhaseOne.first(Prepare.expression(type: "P1a", ballot: ballot)))))
                    When(maxBallot[acceptor] < ballot)
                    maxBallot[acceptor].set(ballot)
                    messages.insert(Message.first(PhaseOne.second(Promise.expression(type: "P1b", ballot: ballot,
                        acceptor: acceptor, maxVBallot: maxVBallot[acceptor], maxValue: maxValue[acceptor]))))
                }
            }
            Do(Step.accept) {
                With(ballots, quorums) { ballot, quorum in
                    When(!proposals.contains { proposal in proposal.ballot == ballot })
                    let replies = promises.filter { reply in reply.ballot == ballot && quorum.contains(reply.acceptor) }
                    When(quorum.allSatisfy { acceptor in replies.contains { reply in reply.acceptor == acceptor } })
                    With(values) { value in
                        When(replies.allSatisfy { reply in reply.maxValue == Value.none }
                            || Select(from: replies) { reply in
                                replies.allSatisfy { other in other.maxVBallot <= reply.maxVBallot }
                            }.maxValue == value)
                        messages.insert(Message.second(PhaseTwo.first(Proposal.expression(type: "P2a", ballot: ballot, value: value))))
                    }
                }
            }
            Do(Step.accepted) {
                With(replicas, ballots, values) { acceptor, ballot, value in
                    When(messages.contains(Message.second(PhaseTwo.first(Proposal.expression(type: "P2a", ballot: ballot, value: value)))))
                    When(maxBallot[acceptor] <= ballot)
                    maxBallot[acceptor].set(ballot)
                    maxVBallot[acceptor].set(ballot)
                    maxValue[acceptor].set(value)
                    messages.insert(Message.second(PhaseTwo.second(Vote.expression(type: "P2b", ballot: ballot,
                        acceptor: acceptor, value: value))))
                }
            }
            let decide = Do(Step.decide) {
                With(ballots, quorums) { ballot, quorum in
                    let replies = votes.filter { vote in vote.ballot == ballot && quorum.contains(vote.acceptor) }
                    When(quorum.allSatisfy { acceptor in replies.contains { vote in vote.acceptor == acceptor } })
                    With(values) { value in
                        When(replies.contains { vote in vote.value == value })
                        decision.set(value)
                    }
                }
            }
            StrongFairness(decide)

            let undecidedOrValue = values.inserting(Value.none)
            let anyOrValue = values.inserting(Value.any)
            let typedPrepares = prepares.allSatisfy { m in m.type == "P1a" && ballots.contains(m.ballot) && m.ballot != 0 }
            let typedPromises = promises.allSatisfy { m in
                m.type == "P1b" && replicas.contains(m.acceptor) && ballots.contains(m.ballot)
                    && ballots.contains(m.maxVBallot) && undecidedOrValue.contains(m.maxValue)
            }
            let typedProposals = proposals.allSatisfy { m in m.type == "P2a" && ballots.contains(m.ballot) && anyOrValue.contains(m.value) }
            let typedVotes = votes.allSatisfy { m in
                m.type == "P2b" && ballots.contains(m.ballot) && replicas.contains(m.acceptor) && values.contains(m.value)
            }
            let PaxosTypeOK = Invariant()
            PaxosTypeOK {
                messages.count == prepares.count + promises.count + proposals.count + votes.count
                typedPrepares && typedPromises && typedProposals && typedVotes
                undecidedOrValue.contains(decision)
                maxBallot.keys == replicas.expr && maxVBallot.keys == replicas.expr && maxValue.keys == replicas.expr
                replicas.allSatisfy { r in ballots.contains(maxBallot[r]) && ballots.contains(maxVBallot[r]) && undecidedOrValue.contains(maxValue[r]) }
            }
            let PaxosNontriviality = Invariant()
            PaxosNontriviality {
                decision == Value.none || proposals.contains { m in m.value == decision }
                promises.allSatisfy { m in
                    (values.contains(m.maxValue) || m.maxVBallot == 0) && (m.maxValue == Value.none || m.maxVBallot > 0)
                }
            }
            let PaxosConsistency = Temporal()
            PaxosConsistency(.alwaysStep(on: decision) { before, after in before == Value.none })
            // Check the selected step property on the full graph; the published CFG also uses symmetry.
            let paxosSymmetry = Symmetry(independently: values, replicas)
            Validation("published") {
                Bind(replicas, to: Set<Replica>([.r1, .r2, .r3, .r4]))
                Bind(values, to: Set<Value>([.v1, .v2, .v3]))
                Bind(quorums, to: Set<Set<Replica>>([[Replica.r1, Replica.r2, Replica.r3], [Replica.r1, Replica.r2, Replica.r4], [Replica.r1, Replica.r3, Replica.r4], [Replica.r2, Replica.r3, Replica.r4]]))
            }
            Validation("symmetricSafety") {
                Bind(replicas, to: Set<Replica>([.r1, .r2, .r3, .r4]))
                Bind(values, to: Set<Value>([.v1, .v2, .v3]))
                Bind(quorums, to: Set<Set<Replica>>([[Replica.r1, Replica.r2, Replica.r3], [Replica.r1, Replica.r2, Replica.r4], [Replica.r1, Replica.r3, Replica.r4], [Replica.r2, Replica.r3, Replica.r4]]))
            }.checking(only: [PaxosTypeOK, PaxosNontriviality]).usingSymmetry(paxosSymmetry)
        }
    }
}

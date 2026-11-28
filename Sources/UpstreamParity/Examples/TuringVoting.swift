// Acceptors raise ballots and vote under quorum rules that preserve agreement.
// The two published Voting configurations share these actions, with different ballot bounds and symmetry.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Paxos/MCVoting.tla
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/PaxosHowToWinATuringAward/Voting.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TuringVotingModel: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case a1, a2, a3
        package static var defaultValue: Self { .a1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2
        package static var defaultValue: Self { .v1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case increase = "IncreaseMaxBal", vote = "VoteFor"
    }

    package static var spec: TLASpec {
        #spec("TuringVoting") { scope in
            Extends(.integers, .finiteSets)
            let MaxBallot = scope.parameter(as: Int.self, in: 1...2)
            let ballots = IntRange(0, through: MaxBallot)
            let acceptors = scope.parameter(as: Set<Member>.self, in: Set<Set<Member>>([Set([.a1, .a2, .a3]), Set([.a1])]))
            let values = scope.parameter(as: Set<Choice>.self, in: Set<Set<Choice>>([Set([.v1, .v2]), Set([.v1])]))
            let quorums = scope.parameter(as: Set<Set<Member>>.self, in: Set<Set<Set<Member>>>([
                Set<Set<Member>>([[Member.a1, Member.a2], [Member.a1, Member.a3], [Member.a2, Member.a3]]), Set<Set<Member>>([[Member.a1]])
            ]))
            let votes = scope.sharedVar(initial: Dictionary<Member, Set<Pair<Int, Choice>>>.mapping(over: acceptors) { _ in
                Set<Pair<Int, Choice>>()
            })
            let maxBal = scope.sharedVar(initial: Dictionary<Member, Int>.mapping(over: acceptors) { _ in -1 })

            Do(Step.increase, over: acceptors, ballots) { a, b in
                When(b > maxBal[a])
                maxBal[a].set(b)
            }
            Do(Step.vote, over: acceptors, ballots, values) { a, b, v in
                When(maxBal[a] <= b)
                When(!votes[a].contains { vote in vote.first() == b })
                When(acceptors.allSatisfy { other in
                    other == a || votes[other].allSatisfy { vote in vote.first() != b || vote.second() == v }
                })
                With(quorums) { quorum in
                    When(quorum.allSatisfy { member in maxBal[member] >= b })
                    let priorBallots = IntRange(-1, through: b - 1).filter { c in
                        c == -1 || quorum.contains { member in votes[member].contains(Pair<Int, Choice>.literal(c, v)) }
                    }
                    let observedBallots = quorum.flatMapping { (member: WithValue<Member>) in
                        votes[member].mapping { (vote: WithValue<Pair<Int, Choice>>) in vote.first() }
                    }
                    When(priorBallots.contains { (c: WithValue<Int>) in
                        !observedBallots.contains { (prior: WithValue<Int>) in c < prior && prior < b }
                    })
                    votes[a].set(votes[a].inserting(Pair<Int, Choice>.literal(b, v)))
                    maxBal[a].set(b)
                }
            }

            let typeOK = votes.keys == acceptors.expr && maxBal.keys == acceptors.expr && acceptors.allSatisfy { a in
                IntRange(-1, through: MaxBallot).contains(maxBal[a])
                    && votes[a].allSatisfy { vote in ballots.contains(vote.first()) && values.contains(vote.second()) }
            }
            let votesSafe = acceptors.allSatisfy { (a: WithValue<Member>) in
                votes[a].allSatisfy { (vote: WithValue<Pair<Int, Choice>>) in
                    IntRange(0, through: vote.first() - 1).allSatisfy { (c: WithValue<Int>) in
                        quorums.contains { (quorum: WithValue<Set<Member>>) in
                            quorum.allSatisfy { (member: WithValue<Member>) in
                                votes[member].contains(Pair<Int, Choice>.literal(c, vote.second()))
                                    || (maxBal[member] > c && !votes[member].contains { (prior: WithValue<Pair<Int, Choice>>) in prior.first() == c })
                            }
                        }
                    }
                }
            }
            let oneValuePerBallot = ballots.allSatisfy { b in
                values.filter { v in
                    acceptors.contains { a in votes[a].contains(Pair<Int, Choice>.literal(b, v)) }
                }.count <= 1
            }
            let Inv = Invariant()
            Inv { typeOK && votesSafe && oneValuePerBallot }
            let chosen = values.filter { v in
                ballots.contains { b in
                    quorums.contains { quorum in
                        quorum.allSatisfy { a in votes[a].contains(Pair<Int, Choice>.literal(b, v)) }
                    }
                }
            }
            let consensus = Instance(of: TuringConsensusModel.self) { Bind(\.Value, projecting: values) }
            let prop_156180051387248000 = Refinement(instance: consensus) { Map(\.chosen, projecting: chosen) }
            let ConsensusSpecBar = Refinement(instance: consensus, behavior: .initialAndNext) {
                Map(\.chosen, projecting: chosen)
            }
            let ballotSymmetry = Symmetry(independently: acceptors, values)
            Validation("published") {
                Bind(quorums, to: Set<Set<Member>>([[Member.a1, Member.a2], [Member.a1, Member.a3], [Member.a2, Member.a3]]))
                Bind(acceptors, to: Set<Member>([.a1, .a2, .a3]))
                Bind(MaxBallot, to: 2)
                Bind(values, to: Set<Choice>([.v1, .v2]))
            }.checking(only: [Inv, prop_156180051387248000]).checkingDeadlock(false)
            Validation("MCVoting") {
                Bind(quorums, to: Set<Set<Member>>([[Member.a1, Member.a2], [Member.a1, Member.a3], [Member.a2, Member.a3]]))
                Bind(acceptors, to: Set<Member>([.a1, .a2, .a3]))
                Bind(MaxBallot, to: 1)
                Bind(values, to: Set<Choice>([.v1, .v2]))
            }.checking(only: [Inv, ConsensusSpecBar]).usingSymmetry(ballotSymmetry).checkingDeadlock(false)
        }
    }
}

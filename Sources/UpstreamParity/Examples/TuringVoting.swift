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
            let acceptors = SetExpr<Member>.literal(.a1, .a2, .a3)
            let values = scope.parameter(as: Set<Choice>.self, in: Set<Set<Choice>>([Set([.v1, .v2])]))
            let quorums = Set<Set<Member>>([
                Set([Member.a1, Member.a2]), Set([Member.a1, Member.a3]), Set([Member.a2, Member.a3])
            ])
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

            let typeOK = votes.keys == acceptors.assuming(Set<Member>.self) && maxBal.keys == acceptors.assuming(Set<Member>.self) && acceptors.allSatisfy { a in
                IntRange(-1, through: MaxBallot).contains(maxBal[a])
                    && votes[a].allSatisfy { vote in ballots.contains(vote.first()) && values.contains(vote.second()) }
            }
            let votesSafe = acceptors.allSatisfy { a in
                votes[a].allSatisfy { vote in
                    IntRange(0, through: vote.first() - 1).allSatisfy { c in
                        quorums.contains { quorum in
                            quorum.allSatisfy { member in
                                votes[member].contains(Pair<Int, Choice>.literal(c, vote.second()))
                                    || (maxBal[member] > c && !votes[member].contains { prior in prior.first() == c })
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
            Invariant("Inv") { typeOK && votesSafe && oneValuePerBallot }
            let chosen = values.filter { v in
                ballots.contains { b in
                    quorums.contains { quorum in
                        quorum.allSatisfy { a in votes[a].contains(Pair<Int, Choice>.literal(b, v)) }
                    }
                }
            }
            let consensus = Instance(of: TuringConsensusModel.self) { Bind(\.Value, projecting: values) }
            consensus
            let prop_156180051387248000 = Refinement(instance: consensus) { Map(\.chosen, projecting: chosen) }
            prop_156180051387248000
            Validation("published") {
                Bind(MaxBallot, to: 2)
                Bind(values, to: Set<Choice>([.v1, .v2]))
            }.checkingDeadlock(false)
        }
    }
}

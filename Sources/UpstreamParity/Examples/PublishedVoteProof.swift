// Acceptors raise their ballot or cast a safe vote. A quorum of matching votes chooses a value.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/byzpaxos/VoteProof.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PublishedVoteProofModel: Sendable {
    package enum Proposal: String, CaseIterable, FiniteTLAValueDomain {
        case one = "v1", two = "v2"
        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Voter: String, CaseIterable, FiniteTLAValueDomain {
        case a1, a2, a3
        package static var defaultValue: Self { .a1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable { case acceptor }

    package static var spec: TLASpec {
        #spec("VoteProof") { configuration in
            let Value = configuration.parameter(as: Set<Proposal>.self, in: Subsets(of: Proposal.all.assuming(Set<Proposal>.self)))
            let Acceptor = configuration.parameter(as: Set<Voter>.self, in: Subsets(of: Voter.all.assuming(Set<Voter>.self)))
            let Ballot = configuration.parameter(as: Set<Int>.self, in: Set<Set<Int>>([Set([0, 1, 2])]))
            let Quorum = configuration.parameter(as: Set<Set<Voter>>.self, in: Set<Set<Set<Voter>>>([
                Set<Set<Voter>>([[.a1, .a2], [.a1, .a3], [.a2, .a3], [.a1, .a2, .a3]])
            ]))
            Assume(!Acceptor.isEmpty)
            Assume(!Value.isEmpty)
            Assume(Quorum.allSatisfy { quorum in quorum.isSubset(of: Acceptor) })
            Assume(Quorum.allSatisfy { first in Quorum.allSatisfy { second in !first.intersection(second).isEmpty } })
            let votes = configuration.sharedVar(initial: Dictionary<Voter, Set<Pair<Int, Proposal>>>.mapping(over: Acceptor) { _ in Set<Pair<Int, Proposal>>() })
            let maxBal = configuration.sharedVar(initial: Dictionary<Voter, Int>.mapping(over: Acceptor) { _ in -1 })

            FormalDefinition("SafeAt", taking: Int.self, Proposal.self, plusCalPhase: .define) { ballot, value -> Expr<Bool> in
                LetRec("SA", over: Ballot, taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, currentBallot) in
                    currentBallot == 0 || Quorum.contains { quorum in
                        quorum.expr.allSatisfy { acceptor in
                            maxBal[acceptor] >= currentBallot.expr
                        } && IntRange(-1, through: currentBallot.expr - 1).contains { priorBallot in
                            ((priorBallot == -1) || (
                                recursion(priorBallot.expr)
                                    && quorum.expr.allSatisfy { acceptor in
                                        Value.allSatisfy { candidate in
                                            !votes[acceptor].contains(Pair<Int, Proposal>.literal(priorBallot.expr, candidate.expr))
                                                || candidate == value
                                        }
                                    }
                            )) && IntRange(priorBallot.expr + 1, through: currentBallot.expr - 1).allSatisfy { laterBallot in
                                quorum.expr.allSatisfy { acceptor in
                                    Value.allSatisfy { candidate in
                                        !votes[acceptor].contains(Pair<Int, Proposal>.literal(laterBallot.expr, candidate.expr))
                                    }
                                }
                            }
                        }
                    }
                }, in: { recursion in
                    recursion(ballot)
                })
            }

            FormalDefinition("ChosenIn", taking: Int.self, Proposal.self, plusCalPhase: .define) { ballot, value -> Expr<Bool> in
                Quorum.contains { quorum in
                    quorum.expr.allSatisfy { acceptor in
                        votes[acceptor].contains(Pair<Int, Proposal>.literal(ballot, value))
                    }
                }
            }

            FormalDefinition(
                "chosen",
                parameters: [],
                body: Value.filter { value in
                    Ballot.contains { ballot in
                        FormalCall(as: Bool.self, "ChosenIn", ballot.expr, value.expr)
                    }
                },
                plusCalPhase: .define,
                dependsOn: ["ChosenIn"]
            )

            Invariant("TypeOK") {
                votes.keys == Acceptor.assuming(Set<Voter>.self)
                maxBal.keys == Acceptor.assuming(Set<Voter>.self)
                Acceptor.allSatisfy { a in
                    votes[a].allSatisfy { vote in Ballot.contains(vote.first()) && Value.contains(vote.second()) }
                        && (maxBal[a] == -1 || Ballot.contains(maxBal[a]))
                }
            }
            Invariant("VInv1") {
                Acceptor.allSatisfy { a in
                    votes[a].allSatisfy { first in
                        votes[a].allSatisfy { second in
                            first.first() != second.first() || first.second() == second.second()
                        }
                    }
                }
            }
            Invariant("VInv2") {
                Acceptor.allSatisfy { a in
                    votes[a].allSatisfy { vote in FormalCall(as: Bool.self, "SafeAt", vote.first(), vote.second()) }
                }
            }
            Invariant("VInv3") {
                Acceptor.allSatisfy { a in
                    Acceptor.allSatisfy { peer in
                        votes[a].allSatisfy { first in
                            votes[peer].allSatisfy { second in
                                first.first() != second.first() || first.second() == second.second()
                            }
                        }
                    }
                }
            }
            Invariant("VInv4") {
                Acceptor.allSatisfy { a in
                    Ballot.allSatisfy { b in
                        maxBal[a] >= b || Value.allSatisfy { v in !votes[a].contains(Pair<Int, Proposal>.literal(b.expr, v.expr)) }
                    }
                }
            }

            let increaseMaxBal = Macro { (ballot: MacroParameter<Int>, acceptor: MacroParameter<Voter>) in
                When(ballot.expr > maxBal[acceptor])
                maxBal.set(maxBal.updating(acceptor, to: ballot.expr))
            }
            let voteFor = Macro { (vote: MacroParameter<Pair<Int, Proposal>>, acceptor: MacroParameter<Voter>) in
                When(
                    maxBal[acceptor] <= vote.expr.first()
                        && Value.allSatisfy { candidate in
                            !votes[acceptor].contains(Pair<Int, Proposal>.literal(vote.expr.first(), candidate.expr))
                        }
                        && Acceptor.removing(acceptor.expr).allSatisfy { peer in
                            Value.allSatisfy { candidate in
                                !votes[peer].contains(Pair<Int, Proposal>.literal(vote.expr.first(), candidate.expr))
                                    || candidate == vote.expr.second()
                            }
                        }
                        && FormalCall(as: Bool.self, "SafeAt", vote.expr.first(), vote.expr.second())
                )
                votes.set(votes.updating(
                    acceptor,
                    to: votes[acceptor].inserting(Pair<Int, Proposal>.literal(vote.expr.first(), vote.expr.second()))
                ))
                maxBal.set(maxBal.updating(acceptor, to: vote.expr.first()))
            }

            Do(Step.acceptor, over: Acceptor) { acceptor in
                With(Ballot) { ballot in
                    Either {
                        increaseMaxBal(ballot.expr, acceptor)
                    } or: {
                        With(Value) { value in
                            voteFor(Pair<Int, Proposal>.literal(ballot.expr, value.expr), acceptor)
                        }
                    }
                }
            }
            let C = Instance(of: ConsensusModel.self) {
                Bind(\.Value, projecting: Value)
            }
            Refinement("Refines", instance: C, behavior: .initialAndNext) {
                Map(\.chosen, projecting: FormalCall(as: Set<Proposal>.self, "chosen"))
            }
            Validation("published") {
                Bind(Value, to: Set<Proposal>([.one, .two]))
                Bind(Acceptor, to: Set<Voter>([.a1, .a2, .a3]))
                Bind(Ballot, to: Set<Int>([0, 1, 2]))
                Bind(Quorum, to: Set<Set<Voter>>([Set([.a1, .a2]), Set([.a1, .a3]), Set([.a2, .a3]), Set([.a1, .a2, .a3])]))
            }.checkingDeadlock(false)
        }
    }
}

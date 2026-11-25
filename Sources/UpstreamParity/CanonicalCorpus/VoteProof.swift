import SwiftTLA
import SwiftTLAMacros

/// The bounded `byzpaxos/VoteProof` model from the upstream PlusCal corpus.
@TLAModel
package struct VoteProofModel: Sendable {
    package static let corpusEntry = CanonicalCorpusEntry(
        id: "voteproof-upstream-port",
        rendered: { try VoteProofModel.render() }
    )

    package enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2
    }

    package enum Acceptor: String, CaseIterable, FiniteTLAValueDomain {
        case a1, a2, a3
    }

    private enum Step: String, CaseIterable {
        case acc
    }

    package static var spec: TLASpec {
        #spec("VoteProof") {
            Constant("Value", SetExpr<Value>(.v1, .v2))
            Constant("Acceptor", SetExpr<Acceptor>(.a1, .a2, .a3))
            Constant("Quorum", SetExpr<SetExpr<Acceptor>>(
                SetExpr<Acceptor>(.a1, .a2),
                SetExpr<Acceptor>(.a1, .a3),
                SetExpr<Acceptor>(.a2, .a3),
                SetExpr<Acceptor>(.a1, .a2, .a3)
            ))
            Constant("Ballot", SetExpr<Int>(0, 1, 2))
            let consensusValue = SetExpr<Value>.literal(.v1, .v2)
            let consensusChosen = FormalCall(as: SetExpr<Value>.self, "chosen")
            let consensusModule = TLASpec("Consensus") {
                Parameter("Value")
                let chosen = Var<SetExpr<Value>>("chosen", SetExpr<Value>())
                Variable(chosen)
                SwiftTLA.Action("Next") {
                    ActionExpr.exists("candidate", from: Parameter("Value")) { candidate in
                        chosen.becomes(SetExpr<Value>.literal(Expr<Value>(candidate)))
                            .when(chosen == SetExpr<Value>())
                    }
                }
                Eventually("Success", !chosen.isEmpty)
            }
            let consensus = Instance(
                "C",
                of: consensusModule,
                plusCalPhase: .postTranslation,
                dependsOn: ["chosen"]
            )
            consensus
            let Refines = Refinement(
                instance: consensus,
                mappings: [
                    .init(FormalModuleParameter("Value"), from: consensusValue),
                    .init(Var<SetExpr<Value>>("chosen"), from: consensusChosen)
                ]
            )
            Refines

            let Voting: Algorithm = Algorithm { scope in
                let votes = scope.sharedVar(initial: Function<Acceptor, SetExpr<Pair<Int, Value>>>.mapping { _ in SetExpr() })
                let maxBal = scope.sharedVar(initial: Function<Acceptor, Int>.mapping { _ in -1 })
                let values = SetExpr<Value>.literal(.v1, .v2)
                let acceptors = SetExpr<Acceptor>.literal(.a1, .a2, .a3)
                let quorums = SetExpr<SetExpr<Acceptor>>.literal(
                    SetExpr<Acceptor>(.a1, .a2),
                    SetExpr<Acceptor>(.a1, .a3),
                    SetExpr<Acceptor>(.a2, .a3),
                    SetExpr<Acceptor>(.a1, .a2, .a3)
                )
                let ballots = SetExpr<Int>.literal(0, 1, 2)

                FormalDefinition("SafeAt", taking: Int.self, Value.self, plusCalPhase: .define) { ballot, value -> Expr<Bool> in
                    LetRec("SA", over: ballots, taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, currentBallot) in
                        currentBallot == 0 || quorums.contains { quorum in
                            quorum.expr.allSatisfy { acceptor in
                                maxBal[acceptor] >= currentBallot.expr
                            } && IntRange(-1, through: currentBallot.expr - 1).contains { priorBallot in
                                ((priorBallot == -1) || (
                                    recursion(priorBallot.expr)
                                        && quorum.expr.allSatisfy { acceptor in
                                            values.allSatisfy { candidate in
                                                !votes[acceptor].contains(Pair<Int, Value>.literal(priorBallot.expr, candidate.expr))
                                                    || candidate == value
                                            }
                                        }
                                )) && IntRange(priorBallot.expr + 1, through: currentBallot.expr - 1).allSatisfy { laterBallot in
                                    quorum.expr.allSatisfy { acceptor in
                                        values.allSatisfy { candidate in
                                            !votes[acceptor].contains(Pair<Int, Value>.literal(laterBallot.expr, candidate.expr))
                                        }
                                    }
                                }
                            }
                        }
                    }, in: { recursion in
                        recursion(ballot)
                    })
                }

                FormalDefinition("ChosenIn", taking: Int.self, Value.self, plusCalPhase: .define) { ballot, value -> Expr<Bool> in
                    quorums.contains { quorum in
                        quorum.expr.allSatisfy { acceptor in
                            votes[acceptor].contains(Pair<Int, Value>.literal(ballot, value))
                        }
                    }
                }

                FormalDefinition(
                    "chosen",
                    parameters: [],
                    body: values.filter { value in
                        ballots.contains { ballot in
                            FormalCall(as: Bool.self, "ChosenIn", ballot.expr, value.expr)
                        }
                    },
                    plusCalPhase: .define,
                    dependsOn: ["ChosenIn"]
                )

                FormalDefinition(
                    "VoteProofTypeOK",
                    parameters: [],
                    body: acceptors.allSatisfy { acceptor in
                        votes[acceptor].allSatisfy { vote in
                            ballots.contains(vote.first()) && values.contains(vote.second())
                        } && ballots.union(SetExpr<Int>.literal(-1)).contains(maxBal[acceptor])
                    },
                    plusCalPhase: .define
                )
                Invariant("TypeOK") { FormalCall(as: Bool.self, "VoteProofTypeOK") }

                FormalDefinition(
                    "VoteProofSingleVotePerBallot",
                    parameters: [],
                    body: acceptors.allSatisfy { acceptor in
                        ballots.allSatisfy { ballot in
                            values.allSatisfy { value in
                                values.allSatisfy { otherValue in
                                    (!votes[acceptor].contains(Pair<Int, Value>.literal(ballot.expr, value.expr))
                                        || !votes[acceptor].contains(Pair<Int, Value>.literal(ballot.expr, otherValue.expr)))
                                        || value == otherValue
                                }
                            }
                        }
                    },
                    plusCalPhase: .define
                )
                Invariant("VInv1") { FormalCall(as: Bool.self, "VoteProofSingleVotePerBallot") }

                FormalDefinition(
                    "VoteProofVotesAreSafe",
                    parameters: [],
                    body: acceptors.allSatisfy { acceptor in
                        ballots.allSatisfy { ballot in
                            values.allSatisfy { value in
                                !votes[acceptor].contains(Pair<Int, Value>.literal(ballot.expr, value.expr))
                                    || FormalCall(as: Bool.self, "SafeAt", ballot.expr, value.expr)
                            }
                        }
                    },
                    plusCalPhase: .define,
                    dependsOn: ["SafeAt"]
                )
                Invariant("VInv2") { FormalCall(as: Bool.self, "VoteProofVotesAreSafe") }

                FormalDefinition(
                    "VoteProofAgreement",
                    parameters: [],
                    body: acceptors.allSatisfy { firstAcceptor in
                        acceptors.allSatisfy { secondAcceptor in
                            ballots.allSatisfy { ballot in
                                values.allSatisfy { firstValue in
                                    values.allSatisfy { secondValue in
                                        (!votes[firstAcceptor].contains(Pair<Int, Value>.literal(ballot.expr, firstValue.expr))
                                            || !votes[secondAcceptor].contains(Pair<Int, Value>.literal(ballot.expr, secondValue.expr)))
                                            || firstValue == secondValue
                                    }
                                }
                            }
                        }
                    },
                    plusCalPhase: .define
                )
                Invariant("VInv3") { FormalCall(as: Bool.self, "VoteProofAgreement") }

                FormalDefinition(
                    "VoteProofChosenValuesAgree",
                    parameters: [],
                    body: FormalCall(as: SetExpr<Value>.self, "chosen").allSatisfy { value in
                        FormalCall(as: SetExpr<Value>.self, "chosen").allSatisfy { otherValue in
                            value == otherValue
                        }
                    },
                    plusCalPhase: .define,
                    dependsOn: ["chosen"]
                )
                Invariant("VInv4") { FormalCall(as: Bool.self, "VoteProofChosenValuesAgree") }

                let increaseMaxBal = Macro { (ballot: MacroParameter<Int>, acceptor: MacroParameter<Acceptor>) in
                    When(ballot.expr > maxBal[acceptor])
                    maxBal.set(maxBal.updating(acceptor, to: ballot.expr))
                }
                let voteFor = Macro { (vote: MacroParameter<Pair<Int, Value>>, acceptor: MacroParameter<Acceptor>) in
                    When(
                        maxBal[acceptor] <= vote.expr.first()
                            && values.allSatisfy { candidate in
                                !votes[acceptor].contains(Pair<Int, Value>.literal(vote.expr.first(), candidate.expr))
                            }
                            && acceptors.removing(acceptor.expr).allSatisfy { peer in
                                values.allSatisfy { candidate in
                                    !votes[peer].contains(Pair<Int, Value>.literal(vote.expr.first(), candidate.expr))
                                        || candidate == vote.expr.second()
                                }
                            }
                            && FormalCall(as: Bool.self, "SafeAt", vote.expr.first(), vote.expr.second())
                    )
                    votes.set(votes.updating(
                        acceptor,
                        to: votes[acceptor].inserting(Pair<Int, Value>.literal(vote.expr.first(), vote.expr.second()))
                    ))
                    maxBal.set(maxBal.updating(acceptor, to: vote.expr.first()))
                }

                Each(Acceptor.all) { selfID in
                    Loop(Step.acc) {
                        With(ballots) { ballot in
                            Either {
                                increaseMaxBal(ballot.expr, selfID.expr)
                            } or: {
                                With(values) { value in
                                    voteFor(Pair<Int, Value>.literal(ballot.expr, value.expr), selfID.expr)
                                }
                            }
                        }
                    }
                }
            }
            Voting
            Validation("VoteProof") {}.checkingDeadlock(false)

        }
    }
}

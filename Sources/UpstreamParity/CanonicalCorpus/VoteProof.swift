import SwiftTLA
import SwiftTLAMacros

/// The bounded `byzpaxos/VoteProof` model from the upstream PlusCal corpus.
@TLAModel
public struct VoteProofModel: Sendable {
    public static let corpusEntry = CanonicalCorpusEntry(
        id: "voteproof-upstream-port",
        specification: { VoteProofModel.spec },
        swiftConfiguration: configuration,
        plusCalConfiguration: configuration
    )

    private static let configuration = CanonicalCorpusConfiguration(
        checks: [
            .init("TypeOK", kind: .invariant),
            .init("VInv1", kind: .invariant),
            .init("VInv2", kind: .invariant),
            .init("VInv3", kind: .invariant),
            .init("VInv4", kind: .invariant),
            .init("Refines", kind: .property)
        ],
        constants: [
            .init("Value", "{\"v1\", \"v2\"}"),
            .init("Acceptor", "{\"a1\", \"a2\", \"a3\"}"),
            .init("Quorum", "{{\"a1\", \"a2\"}, {\"a1\", \"a3\"}, {\"a2\", \"a3\"}, {\"a1\", \"a2\", \"a3\"}}"),
            .init("Ballot", "{0, 1, 2}")
        ],
        checkDeadlock: false
    )

    public enum Value: String, FiniteDomainKey {
        case v1, v2

        public static let formalDomain: [Self] = [.v1, .v2]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.byzpaxos.vote-proof.value")
        public var tlaValue: TLAValue { .string(rawValue) }
        public static var defaultValue: Self { .v1 }

        public init?(formalValue: TLAValue) {
            guard case .string(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    public enum Acceptor: String, FiniteDomainKey {
        case a1, a2, a3

        public static let formalDomain: [Self] = [.a1, .a2, .a3]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.byzpaxos.vote-proof.acceptor")
        public var tlaValue: TLAValue { .string(rawValue) }
        public static var defaultValue: Self { .a1 }

        public init?(formalValue: TLAValue) {
            guard case .string(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case acc
    }

    public static var spec: TLASpec {
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
            let consensus = Instance(
                "C",
                of: ByzPaxosConsensus.module,
                plusCalPhase: .define,
                dependsOn: ["chosen"]
            )
            consensus
            Refinement(
                name: "Refines",
                instance: consensus,
                mappings: [
                    .init(ByzPaxosConsensus.Value, from: consensusValue),
                    .init(ByzPaxosConsensus.chosen, from: consensusChosen)
                ]
            )

            let algorithm: Algorithm = Algorithm("Voting", scoped: { scope in
                let votes = scope.sharedVar("votes", initial: Function<Acceptor, SetExpr<Pair<Int, Value>>>.mapping { _ in SetExpr() })
                let maxBal = scope.sharedVar("maxBal", initial: Function<Acceptor, Int>.mapping { _ in -1 })
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
                        currentBallot == 0 || Exists(in: quorums) { quorum in
                            ForAll(in: quorum.expr) { acceptor in
                                maxBal[acceptor] >= currentBallot.expr
                            } && Exists(in: IntRange(-1, through: currentBallot.expr - 1)) { priorBallot in
                                ((priorBallot == -1) || (
                                    recursion(priorBallot.expr)
                                        && ForAll(in: quorum.expr) { acceptor in
                                            ForAll(in: values) { candidate in
                                                !votes[acceptor].contains(Pair<Int, Value>.literal(priorBallot.expr, candidate.expr))
                                                    || candidate == value
                                            }
                                        }
                                )) && ForAll(in: IntRange(priorBallot.expr + 1, through: currentBallot.expr - 1)) { laterBallot in
                                    ForAll(in: quorum.expr) { acceptor in
                                        ForAll(in: values) { candidate in
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
                    Exists(in: quorums) { quorum in
                        ForAll(in: quorum.expr) { acceptor in
                            votes[acceptor].contains(Pair<Int, Value>.literal(ballot, value))
                        }
                    }
                }

                FormalDefinition(
                    "chosen",
                    parameters: [],
                    body: values.filtering { value in
                        Exists(in: ballots) { ballot in
                            FormalCall(as: Bool.self, "ChosenIn", ballot.expr, value.expr)
                        }.expr
                    },
                    plusCalPhase: .define,
                    dependsOn: ["ChosenIn"]
                )

                FormalDefinition(
                    "VoteProofTypeOK",
                    parameters: [],
                    body: ForAll(in: acceptors) { acceptor in
                        ForAll(in: votes[acceptor]) { vote in
                            ballots.contains(vote.first()) && values.contains(vote.second())
                        } && ballots.union(SetExpr<Int>.literal(-1)).contains(maxBal[acceptor])
                    },
                    plusCalPhase: .define
                )
                Invariant("TypeOK") { FormalCall(as: Bool.self, "VoteProofTypeOK") }

                FormalDefinition(
                    "VoteProofSingleVotePerBallot",
                    parameters: [],
                    body: ForAll(in: acceptors) { acceptor in
                        ForAll(in: ballots) { ballot in
                            ForAll(in: values) { value in
                                ForAll(in: values) { otherValue in
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
                    body: ForAll(in: acceptors) { acceptor in
                        ForAll(in: ballots) { ballot in
                            ForAll(in: values) { value in
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
                    body: ForAll(in: acceptors) { firstAcceptor in
                        ForAll(in: acceptors) { secondAcceptor in
                            ForAll(in: ballots) { ballot in
                                ForAll(in: values) { firstValue in
                                    ForAll(in: values) { secondValue in
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
                    body: ForAll(in: FormalCall(as: SetExpr<Value>.self, "chosen")) { value in
                        ForAll(in: FormalCall(as: SetExpr<Value>.self, "chosen")) { otherValue in
                            value == otherValue
                        }
                    },
                    plusCalPhase: .define,
                    dependsOn: ["chosen"]
                )
                Invariant("VInv4") { FormalCall(as: Bool.self, "VoteProofChosenValuesAgree") }

                let increaseMaxBal = Macro { (ballot: MacroParameter<Int>, acceptor: MacroParameter<Acceptor>) in
                    When(ballot.expr > maxBal[acceptor])
                    Assign(maxBal, to: maxBal.updating(acceptor, to: ballot.expr))
                }
                let voteFor = Macro { (vote: MacroParameter<Pair<Int, Value>>, acceptor: MacroParameter<Acceptor>) in
                    When(
                        maxBal[acceptor] <= vote.expr.first()
                            && ForAll(in: values) { candidate in
                                !votes[acceptor].contains(Pair<Int, Value>.literal(vote.expr.first(), candidate.expr))
                            }
                            && ForAll(in: acceptors.removing(acceptor.expr)) { peer in
                                ForAll(in: values) { candidate in
                                    !votes[peer].contains(Pair<Int, Value>.literal(vote.expr.first(), candidate.expr))
                                        || candidate == vote.expr.second()
                                }
                            }
                            && FormalCall(as: Bool.self, "SafeAt", vote.expr.first(), vote.expr.second())
                    )
                    Assign(votes, to: votes.updating(
                        acceptor,
                        to: votes[acceptor].inserting(Pair<Int, Value>.literal(vote.expr.first(), vote.expr.second()))
                    ))
                    Assign(maxBal, to: maxBal.updating(acceptor, to: vote.expr.first()))
                }

                Each(Acceptor.all) { selfID in
                    While(Step.acc, true) {
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
            })
            algorithm

        }
    }
}

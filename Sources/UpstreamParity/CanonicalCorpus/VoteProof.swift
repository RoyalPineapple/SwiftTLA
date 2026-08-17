import SwiftTLA
import SwiftTLAMacros

/// The bounded `byzpaxos/VoteProof` model from the upstream PlusCal corpus.
@TLAModel
public struct VoteProofModel {
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

    private enum Step: String, PlusCalLabel {
        case acc
    }

    public static var spec: TLASpec {
        #spec("VoteProof") {
            Extends("Integers, NaturalsInduction, FiniteSets, FiniteSetTheorems, WellFoundedInduction, TLC, TLAPS")
            Constant("Value", SetExpr<Value>(.v1, .v2))
            Constant("Acceptor", SetExpr<Acceptor>(.a1, .a2, .a3))
            Constant("Quorum", SetExpr<SetExpr<Acceptor>>(
                SetExpr<Acceptor>(.a1, .a2),
                SetExpr<Acceptor>(.a1, .a3),
                SetExpr<Acceptor>(.a2, .a3),
                SetExpr<Acceptor>(.a1, .a2, .a3)
            ))
            Constant("Ballot", SetExpr<Int>(0, 1, 2))
            Instance("C", of: ByzPaxosConsensus.module)

            Algorithm("Voting") {
                let votes = SharedVar(initial: Function<Acceptor, SetExpr<Pair<Int, Value>>>.mapping { _ in SetExpr() })
                let maxBal = SharedVar(initial: Function<Acceptor, Int>.mapping { _ in -1 })
                let values = SetExpr<Value>.literal(.v1, .v2)
                let acceptors = SetExpr<Acceptor>.literal(.a1, .a2, .a3)
                let quorums = SetExpr<SetExpr<Acceptor>>.literal(
                    SetExpr<Acceptor>(.a1, .a2),
                    SetExpr<Acceptor>(.a1, .a3),
                    SetExpr<Acceptor>(.a2, .a3),
                    SetExpr<Acceptor>(.a1, .a2, .a3)
                )
                let ballots = SetExpr<Int>.literal(0, 1, 2)

                FormalDefinition("SafeAt", taking: Int.self, Value.self) { ballot, value in
                    LetRec("SA", over: ballots, taking: Int.self, { recursion, currentBallot in
                        currentBallot == 0 || Exists(in: quorums) { quorum in
                            ForAll(in: quorum.expr) { acceptor in
                                maxBal[acceptor] >= currentBallot.expr
                            } && Exists(in: IntRange(-1, through: currentBallot.expr - 1)) { priorBallot in
                                ((priorBallot == -1) || (
                                    recursion(priorBallot.expr)
                                        && ForAll(in: quorum.expr) { acceptor in
                                            ForAll(in: values) { candidate in
                                                !votes[acceptor].contains(Pair.literal(priorBallot.expr, candidate.expr))
                                                    || candidate == value
                                            }
                                        }
                                )) && ForAll(in: IntRange(priorBallot.expr + 1, through: currentBallot.expr - 1)) { laterBallot in
                                    ForAll(in: quorum.expr) { acceptor in
                                        ForAll(in: values) { candidate in
                                            !votes[acceptor].contains(Pair.literal(laterBallot.expr, candidate.expr))
                                        }
                                    }
                                }
                            }
                        }
                    }, in: { recursion in
                        recursion(ballot)
                    })
                }

                let increaseMaxBal = Macro { (ballot: MacroParameter<Int>, acceptor: MacroParameter<Acceptor>) in
                    When(ballot.expr > maxBal[acceptor])
                    Assign(maxBal, to: maxBal.updating(acceptor, to: ballot.expr))
                }
                let voteFor = Macro { (vote: MacroParameter<Pair<Int, Value>>, acceptor: MacroParameter<Acceptor>) in
                    When(
                        maxBal[acceptor] <= vote.expr.first()
                            && ForAll(in: values) { candidate in
                                !votes[acceptor].contains(Pair.literal(vote.expr.first(), candidate.expr))
                            }
                            && ForAll(in: acceptors.removing(acceptor.expr)) { peer in
                                ForAll(in: values) { candidate in
                                    !votes[peer].contains(Pair.literal(vote.expr.first(), candidate.expr))
                                        || candidate == vote.expr.second()
                                }
                            }
                            && FormalCall(as: Bool.self, "SafeAt", vote.expr.first(), vote.expr.second())
                    )
                    Assign(votes, to: votes.updating(
                        acceptor,
                        to: votes[acceptor].inserting(Pair.literal(vote.expr.first(), vote.expr.second()))
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
                                    voteFor(Pair.literal(ballot.expr, value.expr), selfID.expr)
                                }
                            }
                        }
                    }
                }
            }

            Definition("ChosenIn(b, v) == \\E Q \\in Quorum : \\A a \\in Q : <<b, v>> \\in votes[a]")
            Definition("chosen == {v \\in Value : \\E b \\in Ballot : ChosenIn(b, v)}")
            Definition("TypeOK == /\\ votes \\in [Acceptor -> SUBSET (Ballot \\X Value)] /\\ maxBal \\in [Acceptor -> Ballot \\cup {-1}]")
            Definition("VInv1 == \\A a \\in Acceptor, b \\in Ballot, v, w \\in Value : <<b, v>> \\in votes[a] /\\ <<b, w>> \\in votes[a] => v = w")
            Definition("VInv2 == \\A a \\in Acceptor, b \\in Ballot, v \\in Value : <<b, v>> \\in votes[a] => SafeAt(b, v)")
            Definition("VInv3 == \\A a1, a2 \\in Acceptor, b \\in Ballot, v1, v2 \\in Value : <<b, v1>> \\in votes[a1] /\\ <<b, v2>> \\in votes[a2] => v1 = v2")
            Definition("VInv4 == \\A v, w \\in Value : v \\in chosen /\\ w \\in chosen => v = w")
            Definition("Refines == C!Spec")
        }
    }
}

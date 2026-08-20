import SwiftTLA
import SwiftTLAMacros

/// The bounded `byzpaxos/VoteProof` model from the upstream PlusCal corpus.
@TLAModel
public struct VoteProofModel: Sendable {
    public static let corpusEntry = CanonicalCorpusEntry(
        id: "voteproof-upstream-port",
        specification: { VoteProofModel.spec },
        swiftConfiguration: configuration,
        plusCalConfiguration: configuration,
        externalInputs: [
            .init(name: "NaturalsInduction", source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/NaturalsInduction.tla"), sha256: "08f52420cdaaf11292ed366782b5ce5b596bb7cbe789526a1cfd8806dbf98624"),
            .init(name: "WellFoundedInduction", source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/WellFoundedInduction.tla"), sha256: "6f2f274c2e987d1edcf004d8e37b053f1f82b912e66d6a51bae0af8012ddcbec"),
            .init(name: "FiniteSetTheorems", source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/FiniteSetTheorems.tla"), sha256: "484bf0f9ab6a69ef45f7282f7f92dcf1e6ae139e44117b0d5a4427635818e773"),
            .init(name: "TLAPS", source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/TLAPS.tla"), sha256: "9afe54984062748a0568966434cc0945d682f8cd89fdbc38f73b5579751b0c55"),
            .init(name: "Functions", source: .init(repository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422", path: "modules/Functions.tla"), sha256: "b54ff63b7c76c327525c17c188d5f9f5e53d92f3fd701f5e2ba54f0f54391063"),
            .init(name: "Folds", source: .init(repository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422", path: "modules/Folds.tla"), sha256: "aa59063fd600bb640b2ae24dc85ef770277ef5bf7955092b76b8b471790086da")
        ]
    )

    private static let configuration = CanonicalCorpusConfiguration(
        checks: [
            .init("TypeOK", kind: .invariant, support: .externalOnly(reason: externalReason)),
            .init("VInv1", kind: .invariant, support: .externalOnly(reason: externalReason)),
            .init("VInv2", kind: .invariant, support: .externalOnly(reason: externalReason)),
            .init("VInv3", kind: .invariant, support: .externalOnly(reason: externalReason)),
            .init("VInv4", kind: .invariant, support: .externalOnly(reason: externalReason)),
            .init("Refines", kind: .property, support: .externalOnly(reason: externalReason))
        ],
        constants: [
            .init("Value", "{\"v1\", \"v2\"}"),
            .init("Acceptor", "{\"a1\", \"a2\", \"a3\"}"),
            .init("Quorum", "{{\"a1\", \"a2\"}, {\"a1\", \"a3\"}, {\"a2\", \"a3\"}, {\"a1\", \"a2\", \"a3\"}}"),
            .init("Ballot", "{0, 1, 2}")
        ],
        checkDeadlock: false
    )

    private static let externalReason = "The upstream VoteProof claims use TLA+ constructs outside SwiftTLA's supported property DSL."

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
            Instance("C", of: ByzPaxosConsensus.module, plusCalPhase: .define, dependsOn: ["chosen"])

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

                FormalDefinition("SafeAt", taking: Int.self, Value.self, plusCalPhase: .define) { ballot, value in
                    LetRec("SA", over: ballots, taking: Int.self, { (recursion: LocalRecursion<Int, Bool>, currentBallot) in
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

            Definition("ChosenIn(b, v) == \\E Q \\in Quorum : \\A a \\in Q : <<b, v>> \\in votes[a]", named: "ChosenIn", plusCalPhase: .define)
            Definition("chosen == {v \\in Value : \\E b \\in Ballot : ChosenIn(b, v)}", named: "chosen", plusCalPhase: .define, dependsOn: ["ChosenIn"])
            Definition("TypeOK == /\\ votes \\in [Acceptor -> SUBSET (Ballot \\X Value)] /\\ maxBal \\in [Acceptor -> Ballot \\cup {-1}]", named: "TypeOK", plusCalPhase: .define)
            Definition("VInv1 == \\A a \\in Acceptor, b \\in Ballot, v, w \\in Value : <<b, v>> \\in votes[a] /\\ <<b, w>> \\in votes[a] => v = w", named: "VInv1", plusCalPhase: .define)
            Definition("VInv2 == \\A a \\in Acceptor, b \\in Ballot, v \\in Value : <<b, v>> \\in votes[a] => SafeAt(b, v)", named: "VInv2", plusCalPhase: .define, dependsOn: ["SafeAt"])
            Definition("VInv3 == \\A a1, a2 \\in Acceptor, b \\in Ballot, v1, v2 \\in Value : <<b, v1>> \\in votes[a1] /\\ <<b, v2>> \\in votes[a2] => v1 = v2", named: "VInv3", plusCalPhase: .define)
            Definition("VInv4 == \\A v, w \\in Value : v \\in chosen /\\ w \\in chosen => v = w", named: "VInv4", plusCalPhase: .define, dependsOn: ["chosen"])
            Definition("Refines == C!Spec", named: "Refines", plusCalPhase: .define, dependsOn: ["C"])
        }
    }
}

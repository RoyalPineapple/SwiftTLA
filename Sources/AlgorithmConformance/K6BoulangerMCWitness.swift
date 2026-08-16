import SwiftTLA
import SwiftTLAMacros

/// K6 bounded Boulangerie witness from Boulanger.tla and MCBoulanger.cfg.
///
/// This is a direct PlusCal-shaped port of the published model: each label
/// is one atomic region, and the `Either`, `With`, `Choose`, and `Goto`
/// blocks preserve the source control flow. The ticket choice is bounded by
/// the upstream finite choice and state-constraint bounds.
@TLAModel
public struct K6BoulangerMCWitness {
    public enum Process: Int, FiniteDomainKey {
        case one = 1
        case two = 2
        case three = 3

        public static let formalDomain: [Self] = [.one, .two, .three]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.boulanger.process")
    }

    private enum Label: String, PlusCalLabel {
        case ncs, e1, e2, e3, e4, w1, w2, cs, exit
    }

    public static var spec: TLASpec {
        #spec("Boulanger") {
            Extends("Integers")
            Algorithm("Boulanger") {
                let num = SharedVar(initial: Function<Process, Int>.literal(
                    (.one, 0), (.two, 0), (.three, 0)
                ))
                let flag = SharedVar(initial: Function<Process, Bool>.literal(
                    (.one, false), (.two, false), (.three, false)
                ))
                Each(Process.all, fairness: .weak) { selfID in
                    let unchecked = LocalVar(initial: SetExpr<Process>())
                    let max = LocalVar(initial: 0)
                    let nxt = LocalVar(initial: Process.one)
                    let previous = LocalVar(initial: -1)

                    Do(Label.ncs) { Skip() }

                    Do(Label.e1) {
                        Either {
                            Assign(flag, to: flag.updating(
                                selfID,
                                to: If(flag[selfID] == true, then: false, else: true)
                            ))
                            Goto(Label.e1)
                        } or: {
                            Assign(flag, to: flag.updating(selfID, to: true))
                            Assign(unchecked, to: SetExpr<Process>.literal(.one, .two, .three).removing(selfID))
                            Assign(max, to: 0)
                        }
                    }

                    While(Label.e2, !unchecked.isEmpty) {
                        With(unchecked) { process in
                            Assign(unchecked, to: unchecked.removing(process))
                            If(num[process] > max) {
                                Assign(max, to: num[process])
                            }
                        }
                    }

                    Do(Label.e3) {
                        Either {
                            Choose(0...3) { ticket in
                                Assign(num, to: num.updating(selfID, to: ticket.expr))
                                Goto(Label.e3)
                            }
                        } or: {
                            Assign(num, to: num.updating(selfID, to: max + 1))
                        }
                    }

                    Do(Label.e4) {
                        Either {
                            Assign(flag, to: flag.updating(
                                selfID,
                                to: If(flag[selfID] == true, then: false, else: true)
                            ))
                            Goto(Label.e4)
                        } or: {
                            Assign(flag, to: flag.updating(selfID, to: false))
                            Assign(unchecked, to: If(
                                num[selfID] == 1,
                                then: Process.all.members(before: selfID),
                                else: SetExpr<Process>.literal(.one, .two, .three).removing(selfID)
                            ))
                        }
                    }

                    While(Label.w1, !unchecked.isEmpty) {
                        With(unchecked) { process in
                            Assign(nxt, to: process.expr)
                            When(!flag[process])
                            Assign(previous, to: -1)
                            Goto(Label.w2)
                        }
                    }

                    Do(Label.w2) {
                        If(
                            num[nxt] == 0
                                || num[selfID] < num[nxt]
                                || (num[selfID] == num[nxt]
                                    && Process.all.members(before: nxt).contains(selfID))
                                || (previous != -1 && num[nxt] != previous)
                        ) {
                            Assign(unchecked, to: unchecked.removing(nxt.expr))
                            If(unchecked.isEmpty) {
                                Goto(Label.cs)
                            } else: {
                                Goto(Label.w1)
                            }
                        } else: {
                            Assign(previous, to: num[nxt])
                            Goto(Label.w2)
                        }
                    }

                    Do(Label.cs) { Skip() }

                    Do(Label.exit) {
                        Either {
                            Choose(0...3) { ticket in
                                Assign(num, to: num.updating(selfID, to: ticket.expr))
                                Goto(Label.exit)
                            }
                        } or: {
                            Assign(num, to: num.updating(selfID, to: 0))
                            Goto(Label.ncs)
                        }
                    }

                    // These are the process-local parts of the source
                    // `TypeOK` property. The lowerer quantifies them over
                    // every process, so the public DSL never exposes the
                    // generated formal functions for local state.
                    Invariant("LocalTypeOK") {
                        max >= 0 && previous >= -1
                    }
                }

                // The upstream TLC configuration retains only tickets below 3.
                // The concrete `Choose(0...3)` is already finite here, so the
                // fixture carries the equivalent state constraint directly
                // instead of a non-existent `NatOverride` helper module.
                StateConstraint(All(Process.all) { process in num[process] < 3 })

                Invariant("MutualExclusion") {
                    All(Process.all) { first in
                        All(Process.all) { second in
                            first == second || !(At(Label.cs, first) && At(Label.cs, second))
                        }
                    }
                }
            }
        }
    }
}

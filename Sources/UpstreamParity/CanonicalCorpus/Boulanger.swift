import SwiftTLA
import SwiftTLAMacros

/// The bounded `Boulanger` process-control model from the upstream PlusCal
/// corpus. The bound and state constraint match MCBoulanger.
@TLAModel
public struct BoulangerModel: Sendable {
    public static let corpusEntry = CanonicalCorpusEntry(
        id: "boulanger-upstream-port",
        specification: { BoulangerModel.spec },
        swiftConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        plusCalConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n"
    )

    public enum Process: Int, FiniteDomainKey {
        case one = 1
        case two = 2

        public static let formalDomain: [Self] = [.one, .two]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.boulanger.process")
    }

    private enum Label: String, PlusCalLabel {
        case ncs, e1, e2, e3, e4, w1, w2, cs, exit
    }

    public static var spec: TLASpec {
        #spec("Boulanger") {
            Extends("Integers")
            Algorithm("Boulanger") {
                let num = SharedVar(initial: Function<Process, Int>.literal((.one, 0), (.two, 0)))
                let flag = SharedVar(initial: Function<Process, Bool>.literal((.one, false), (.two, false)))

                Each(Process.all, fairness: .weak) { selfID in
                    let unchecked = LocalVar(initial: SetExpr<Process>())
                    let max = LocalVar(initial: 0)
                    let nxt = LocalVar(initial: Process.one)
                    let previous = LocalVar(initial: -1)

                    Do(Label.ncs) { Skip() }

                    Do(Label.e1) {
                        Either {
                            Assign(flag, to: flag.updating(selfID, to: If(flag[selfID] == true, then: false, else: true)))
                            Goto(Label.e1)
                        } or: {
                            Assign(flag, to: flag.updating(selfID, to: true))
                            Assign(unchecked, to: SetExpr<Process>.literal(.one, .two).removing(selfID))
                            Assign(max, to: 0)
                        }
                    }

                    While(Label.e2, !unchecked.isEmpty) {
                        With(unchecked) { process in
                            Assign(unchecked, to: unchecked.removing(process))
                            If(num[process] > max) { Assign(max, to: num[process]) }
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
                            Assign(flag, to: flag.updating(selfID, to: If(flag[selfID] == true, then: false, else: true)))
                            Goto(Label.e4)
                        } or: {
                            Assign(flag, to: flag.updating(selfID, to: false))
                            Assign(unchecked, to: If(num[selfID] == 1, then: Process.all.members(before: selfID), else: SetExpr<Process>.literal(.one, .two).removing(selfID)))
                        }
                    }

                    Do(Label.w1) {
                        If(!unchecked.isEmpty) {
                            With(unchecked) { process in
                                Assign(nxt, to: process.expr)
                                When(!flag[process])
                                Assign(previous, to: -1)
                                Goto(Label.w2)
                            }
                        } else: { Goto(Label.cs) }
                    }

                    Do(Label.w2) {
                        If(num[nxt] == 0 || num[selfID] < num[nxt] || (num[selfID] == num[nxt] && Process.all.members(before: nxt).contains(selfID)) || (previous != -1 && num[nxt] != previous)) {
                            Let(unchecked.removing(nxt.expr)) { remaining in
                                Assign(unchecked, to: remaining.expr)
                                If(remaining.expr.isEmpty) { Goto(Label.cs) } else: { Goto(Label.w1) }
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

                    Invariant("LocalTypeOK") { max >= 0 && previous >= -1 }
                }

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

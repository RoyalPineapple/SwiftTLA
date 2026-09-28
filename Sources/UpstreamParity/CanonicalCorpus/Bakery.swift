import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BakeryModel: Sendable {
    package static let corpusEntry = CanonicalCorpusEntry(
        id: "bakery-upstream-port",
        rendered: { try BakeryModel.validationScenarios()[0].render() }
    )

    private enum Label: String, CaseIterable {
        case ncs, e1, e2, e3, e4, w1, w2, cs, exit
    }

    package static var spec: TLASpec {
        #spec("Bakery") { scope in
            Extends(.integers)
            let N = scope.parameter(as: Int.self, in: 1...2)
            let MaxNat = scope.parameter(as: Int.self, in: 0...2)
            let Procs: Expr<Set<Int>> = IntRange(1, through: N)
            let Nat: Expr<Set<Int>> = IntRange(0, through: MaxNat)
            let TypeOK = Invariant()
            let Inv = Invariant()
            let MutualExclusion = Invariant()

            Algorithm("Bakery", scoped: { scope in
                let num: SharedVariable<[Int: Int]> = scope.sharedVar(in: Functions(from: Procs, to: Nat))
                let flag: SharedVariable<[Int: Bool]> = scope.sharedVar(in: Functions(from: Procs, to: Set<Bool>([false, true])))

                Each(Procs, fairness: .weak(excluding: [Label.ncs]), scoped: { (selfID: ProcessIdentifier<Int>, scope: ProcessScope) in
                    let unchecked: LocalVariable<Set<Int>> = scope.localVar(in: Subsets(of: Procs))
                    let max: LocalVariable<Int> = scope.localVar(in: Nat)
                    let nxt: LocalVariable<Int> = scope.localVar(in: Procs)
                    let uncheckeds = unchecked.family(for: Int.self)
                    let maxima = max.family(for: Int.self)
                    let nextMembers = nxt.family(for: Int.self)

                    Do(Label.ncs) { Skip() }

                    Do(Label.e1) {
                        Either {
                            Assign(flag[selfID], to: !flag[selfID])
                            Goto(Label.e1)
                        } or: {
                            Assign(flag[selfID], to: true)
                            Assign(unchecked, to: Procs.removing(selfID))
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
                            With(Nat) { ticket in
                                Assign(num[selfID], to: ticket.expr)
                                Goto(Label.e3)
                            }
                        } or: {
                            With(Nat) { ticket in
                                When(ticket.expr > max)
                                Assign(num[selfID], to: ticket.expr)
                            }
                        }
                    }

                    Do(Label.e4) {
                        Either {
                            Assign(flag[selfID], to: !flag[selfID])
                            Goto(Label.e4)
                        } or: {
                            Assign(flag[selfID], to: false)
                            Assign(unchecked, to: Procs.removing(selfID))
                        }
                    }

                    Do(Label.w1) {
                        If(!unchecked.isEmpty) {
                            With(unchecked) { process in
                                Assign(nxt, to: process.expr)
                                When(!flag[process])
                                Goto(Label.w2)
                            }
                        } else: { Goto(Label.cs) }
                    }

                    Do(Label.w2) {
                        When(num[nxt] == 0 || num[selfID] < num[nxt]
                            || (num[selfID] == num[nxt] && selfID < nxt))
                        Assign(unchecked, to: unchecked.removing(nxt.expr))
                        Goto(Label.w1)
                    }

                    Do(Label.cs) { Skip() }

                    Do(Label.exit) {
                        Either {
                            With(Nat) { ticket in
                                Assign(num[selfID], to: ticket.expr)
                                Goto(Label.exit)
                            }
                        } or: {
                            Assign(num[selfID], to: 0)
                            Goto(Label.ncs)
                        }
                    }

                    let domainsOK: Expr<Bool> = num.keys == Procs && flag.keys == Procs
                        && uncheckeds.keys == Procs && maxima.keys == Procs && nextMembers.keys == Procs
                    let valuesOK: Expr<Bool> = Nat.contains(num[selfID])
                        && Set<Bool>([false, true]).contains(flag[selfID])
                        && unchecked.isSubset(of: Procs) && Nat.contains(max) && Procs.contains(nxt)
                    let locationOK: Expr<Bool> = At(Label.ncs, selfID) || At(Label.e1, selfID)
                        || At(Label.e2, selfID) || At(Label.e3, selfID) || At(Label.e4, selfID)
                        || At(Label.w1, selfID) || At(Label.w2, selfID) || At(Label.cs, selfID)
                        || At(Label.exit, selfID)
                    let typeOK: Expr<Bool> = domainsOK && valuesOK && locationOK
                    let activeTicket: Expr<Bool> = !(At(Label.e4, selfID) || At(Label.w1, selfID)
                        || At(Label.w2, selfID) || At(Label.cs, selfID)) || num[selfID] != 0
                    let choosingFlag: Expr<Bool> = !(At(Label.e2, selfID) || At(Label.e3, selfID)) || flag[selfID]
                    let distinctNext: Expr<Bool> = !At(Label.w2, selfID) || nxt != selfID
                    let excludesSelf: Expr<Bool> = !(At(Label.w1, selfID) || At(Label.w2, selfID))
                        || !unchecked.contains(selfID)
                    let observedMaximum: Expr<Bool> = !(At(Label.w2, selfID)
                        && ((At(Label.e2, nxt) && !uncheckeds[nxt].contains(selfID)) || At(Label.e3, nxt)))
                        || maxima[nxt] >= num[selfID]

                    TypeOK { typeOK }
                    Inv {
                        typeOK && activeTicket && choosingFlag && distinctNext
                            && excludesSelf && observedMaximum
                            && ForAll(in: Procs) { (other: WithValue<Int>) -> Expr<Bool> in
                                let passedMember = (At(Label.w1, selfID) || At(Label.w2, selfID))
                                    && !unchecked.contains(other) && other != selfID
                                let criticalMember = At(Label.cs, selfID) && other != selfID
                                let idle = At(Label.ncs, other) || At(Label.e1, other) || At(Label.exit, other)
                                let scanning = At(Label.e2, other)
                                    && (uncheckeds[other].contains(selfID) || maxima[other] >= num[selfID])
                                let choosing = At(Label.e3, other) && maxima[other] >= num[selfID]
                                let waiting = At(Label.w1, other) || At(Label.w2, other)
                                let laterTicket = num[selfID] < num[other]
                                    || (num[selfID] == num[other] && selfID < other)
                                let competing = (At(Label.e4, other) || waiting) && laterTicket
                                    && (!waiting || uncheckeds[other].contains(selfID))
                                let before = num[selfID] > 0 && (idle || scanning || choosing || competing)
                                return !(passedMember || criticalMember) || before
                            }
                    }
                })

                MutualExclusion {
                    ForAll(in: Procs) { first in
                        ForAll(in: Procs) { second in
                            first == second || !(At(Label.cs, first) && At(Label.cs, second))
                        }
                    }
                }
            })
            InitialStates(satisfying: Inv)
            Validation("MCBakery") {
                Bind(N, to: 2)
                Bind(MaxNat, to: 2)
            }.checking(only: [MutualExclusion, TypeOK, Inv])
                .checkingDeadlock(false)
                .behavior(.initialAndNext)
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BoulangerModel: Sendable {
    package static let corpusEntry = CanonicalCorpusEntry(
        id: "boulanger-upstream-port",
        rendered: { try BoulangerModel.validationScenarios()[0].render() }
    )

    private enum Label: String, CaseIterable {
        case ncs, e1, e2, e3, e4, w1, w2, cs, exit
    }

    package static var spec: TLASpec {
        #spec("Boulanger") { scope in
            Extends(.integers)
            let N = scope.parameter(as: Int.self, in: 1...3)
            let MaxNat = scope.parameter(as: Int.self, in: 1...3)
            let Procs: Expr<Set<Int>> = IntRange(1, through: N)
            Assume(IntRange(0, through: MaxNat).contains(N))
            let TypeOK = Invariant()
            let Inv = Invariant()
            let MutualExclusion = Invariant()
            Algorithm("Boulanger", scoped: { scope in
                let num: SharedVariable<[Int: Int]> = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Procs) { _ in 0 })
                let flag: SharedVariable<[Int: Bool]> = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: Procs) { _ in false })

                Each(Procs, fairness: .weak(excluding: [Label.ncs]), scoped: { (selfID: ProcessIdentifier<Int>, scope: ProcessScope) in
                    let unchecked: LocalVariable<Set<Int>> = scope.localVar(initial: Set<Int>())
                    let max: LocalVariable<Int> = scope.localVar(initial: 0)
                    let nxt: LocalVariable<Int> = scope.localVar(initial: 1)
                    let previous: LocalVariable<Int> = scope.localVar(initial: -1)
                    let uncheckeds = unchecked.family(for: Int.self)
                    let maxima = max.family(for: Int.self)
                    let nextMembers = nxt.family(for: Int.self)
                    let previousValues = previous.family(for: Int.self)
                    let domainsOK: Expr<Bool> = num.keys == Procs && flag.keys == Procs
                        && uncheckeds.keys == Procs && maxima.keys == Procs
                        && nextMembers.keys == Procs && previousValues.keys == Procs
                    let valuesOK: Expr<Bool> = IntRange(0, through: MaxNat).contains(num[selfID])
                        && Set<Bool>([false, true]).contains(flag[selfID])
                        && unchecked.isSubset(of: Procs)
                        && IntRange(0, through: MaxNat).contains(max)
                        && Procs.contains(nxt)
                        && IntRange(-1, through: MaxNat).contains(previous)
                    let locationOK: Expr<Bool> = At(Label.ncs, selfID) || At(Label.e1, selfID)
                            || At(Label.e2, selfID) || At(Label.e3, selfID)
                            || At(Label.e4, selfID) || At(Label.w1, selfID)
                            || At(Label.w2, selfID) || At(Label.cs, selfID)
                            || At(Label.exit, selfID)
                    let typeOK: Expr<Bool> = domainsOK && valuesOK && locationOK
                    let inactiveTicket: Expr<Bool> = !(At(Label.ncs, selfID) || At(Label.e1, selfID) || At(Label.e2, selfID)) || num[selfID] == 0
                    let activeTicket: Expr<Bool> = !(At(Label.e4, selfID) || At(Label.w1, selfID) || At(Label.w2, selfID) || At(Label.cs, selfID)) || num[selfID] != 0
                    let choosingFlag: Expr<Bool> = !(At(Label.e2, selfID) || At(Label.e3, selfID)) || flag[selfID]
                    let distinctNext: Expr<Bool> = !At(Label.w2, selfID) || nxt != selfID
                    let excludesSelf: Expr<Bool> = !(At(Label.e2, selfID) || At(Label.w1, selfID) || At(Label.w2, selfID)) || !unchecked.contains(selfID)
                    let observedMaximum: Expr<Bool> = !(At(Label.w2, selfID)
                        && ((At(Label.e2, nxt) && !uncheckeds[nxt].contains(selfID)) || At(Label.e3, nxt)))
                        || maxima[nxt] >= num[selfID]
                    let localInvariant: Expr<Bool> = inactiveTicket && activeTicket && choosingFlag
                        && distinctNext && excludesSelf && observedMaximum

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
                            With(IntRange(0, through: MaxNat)) { ticket in
                                Assign(num[selfID], to: ticket.expr)
                                Goto(Label.e3)
                            }
                        } or: {
                            Assign(num[selfID], to: max + 1)
                        }
                    }

                    Do(Label.e4) {
                        Either {
                            Assign(flag[selfID], to: !flag[selfID])
                            Goto(Label.e4)
                        } or: {
                            Assign(flag[selfID], to: false)
                            Assign(unchecked, to: If(num[selfID] == 1,
                                then: IntRange(1, through: selfID - 1), else: Procs.removing(selfID)))
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
                        If(num[nxt] == 0 || num[selfID] < num[nxt] || (num[selfID] == num[nxt] && selfID < nxt) || (previous != -1 && num[nxt] != previous)) {
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
                            With(IntRange(0, through: MaxNat)) { ticket in
                                Assign(num[selfID], to: ticket.expr)
                                Goto(Label.exit)
                            }
                        } or: {
                            Assign(num[selfID], to: 0)
                            Goto(Label.ncs)
                        }
                    }

                    TypeOK { typeOK }
                    Inv {
                        typeOK
                            && localInvariant
                            && ForAll(in: Procs) { (other: WithValue<Int>) -> Expr<Bool> in
                                let passedMember: Expr<Bool> = (At(Label.w1, selfID) || At(Label.w2, selfID))
                                    && !unchecked.contains(other) && other != selfID
                                let nextCompeting = At(Label.e4, nxt) || At(Label.w1, nxt)
                                    || At(Label.w2, nxt) || At(Label.cs, nxt)
                                let changedTicket = At(Label.w2, selfID) && previous != -1
                                    && previous != num[nxt] && nextCompeting && other == nxt
                                let criticalMember = At(Label.cs, selfID) && other != selfID
                                let requiresBefore = passedMember || changedTicket || criticalMember
                                let idle = At(Label.ncs, other) || At(Label.e1, other) || At(Label.exit, other)
                                let laterMaximum = maxima[other] >= num[selfID]
                                    || (other > selfID && maxima[other] + 1 == num[selfID])
                                let scanning = At(Label.e2, other)
                                    && (uncheckeds[other].contains(selfID) || laterMaximum)
                                let choosing = At(Label.e3, other) && laterMaximum
                                let waiting = At(Label.w1, other) || At(Label.w2, other)
                                let laterTicket = num[selfID] < num[other]
                                    || (num[selfID] == num[other] && selfID < other)
                                let competing = (At(Label.e4, other) || waiting) && laterTicket
                                    && (!waiting || uncheckeds[other].contains(selfID))
                                let firstTicket = num[selfID] == 1 && selfID < other
                                let before = num[selfID] > 0 && (idle || scanning || choosing || competing || firstTicket)
                                return !requiresBefore || before
                            }
                    }
                })

                StateConstraint(ForAll(in: Procs) { process in num[process] < MaxNat })
                MutualExclusion {
                    ForAll(in: Procs) { first in
                        ForAll(in: Procs) { second in
                            first == second || !(At(Label.cs, first) && At(Label.cs, second))
                        }
                    }
                }
            })
            Validation("MCBoulanger") {
                Bind(N, to: 3)
                Bind(MaxNat, to: 3)
            }
        }
    }
}

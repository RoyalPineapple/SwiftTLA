import SwiftTLA
import SwiftTLAMacros

/// The bounded N=2 instance of Lamport's PlusCal Bakery algorithm.
///
/// The source algorithm is authored as one fair process family. The lowerer
/// creates the function-shaped process-local state and program counter that
/// the upstream PlusCal translator creates.
@TLAModel
package struct BakeryN2Model: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case ncs
        case e1
        case e2
        case e3
        case e4
        case w1
        case w2
        case cs
        case exit
    }

    package static var spec: TLASpec {
        #spec("Bakery") {
            Extends(.integers)
            Algorithm("Bakery", scoped: { scope in
                let num = scope.sharedVar("num", initial: Function<Process, Int>.literal((.one, 0), (.two, 0)))
                let flag = scope.sharedVar("flag", initial: Function<Process, Bool>.literal((.one, false), (.two, false)))

                Each(Process.all, fairness: .weak, scoped: { process, scope in
                    let unchecked: LocalVariable<SetExpr<Process>> = scope.localVar("unchecked", initial: SetExpr<Process>())
                    let maxSeen = scope.localVar("maxSeen", initial: 0)
                    let next: LocalVariable<Process> = scope.localVar("next", initial: .one)

                    Do(Step.ncs) {
                        Skip()
                    }

                    Do(Step.e1) {
                        Either {
                            Assign(flag, to: flag.updating(process, to: !flag[process]))
                            Goto(Step.e1)
                        } or: {
                            Assign(flag, to: flag.updating(process, to: true))
                            Assign(unchecked, to: SetExpr<Process>.literal(.one, .two).removing(process))
                            Assign(maxSeen, to: 0)
                        }
                    }

                    While(Step.e2, !unchecked.expr.isEmpty) {
                        With(unchecked) { candidate in
                            Assign(unchecked, to: unchecked.expr.removing(candidate))
                            If(num[candidate] > maxSeen.expr) {
                                Assign(maxSeen, to: num[candidate])
                            }
                        }
                    }

                    Do(Step.e3) {
                        Either {
                            With(SetExpr<Int>.literal(0, 1, 2)) { ticket in
                                Assign(num, to: num.updating(process, to: ticket.expr))
                                Goto(Step.e3)
                            }
                        } or: {
                            With(SetExpr<Int>.literal(0, 1, 2)) { ticket in
                                When(ticket.expr > maxSeen.expr)
                                Assign(num, to: num.updating(process, to: ticket.expr))
                            }
                        }
                    }

                    Do(Step.e4) {
                        Either {
                            Assign(flag, to: flag.updating(process, to: !flag[process]))
                            Goto(Step.e4)
                        } or: {
                            Assign(flag, to: flag.updating(process, to: false))
                            Assign(unchecked, to: SetExpr<Process>.literal(.one, .two).removing(process))
                        }
                    }

                    Do(Step.w1) {
                        Either {
                            When(unchecked.expr.isEmpty)
                            Goto(Step.cs)
                        } or: {
                            With(unchecked) { candidate in
                                Assign(next, to: candidate)
                                When(!flag[candidate])
                                Goto(Step.w2)
                            }
                        }
                    }

                    Do(Step.w2) {
                        Either {
                            When(num[next.expr] == 0)
                            Assign(unchecked, to: unchecked.expr.removing(next.expr))
                            Goto(Step.w1)
                        } or: {
                            Either {
                                When(num[process] < num[next.expr])
                                Assign(unchecked, to: unchecked.expr.removing(next.expr))
                                Goto(Step.w1)
                            } or: {
                                When(num[process] == num[next.expr])
                                When(process.stateExpr < next.expr)
                                Assign(unchecked, to: unchecked.expr.removing(next.expr))
                                Goto(Step.w1)
                            }
                        }
                    }

                    Do(Step.cs) {
                        Skip()
                    }

                    Do(Step.exit) {
                        Either {
                            With(SetExpr<Int>.literal(0, 1, 2)) { ticket in
                                Assign(num, to: num.updating(process, to: ticket.expr))
                                Goto(Step.exit)
                            }
                        } or: {
                            Assign(num, to: num.updating(process, to: 0))
                            Goto(Step.ncs)
                        }
                    }
                })
            })
        }
    }
}

extension Example {
    package static let bakeryN2 = Entry(
        id: "Bakery/N2",
        upstreamSpec: "Bakery-Boulangerie",
        upstreamModule: "specifications/Bakery-Boulangerie/Bakery.tla",
        upstreamCfg: "specifications/Bakery-Boulangerie/MCBakery.cfg",
        expectedDistinct: 2303,
        spec: BakeryN2Model.spec,
        notes: "N=2, MaxNat=2. One fair PlusCal process family lowered to typed functions and program counters."
    )
}

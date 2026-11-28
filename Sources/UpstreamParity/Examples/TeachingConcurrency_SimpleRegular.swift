// The same concurrency exercise models overlapping writes to regular registers.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TeachingConcurrency/SimpleRegular.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/TeachingConcurrency/SimpleRegular.tla, SimpleRegular.cfg (N = 8).
@TLAModel
package struct TeachingSimpleRegularN8Model: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case p0, p1, p2, p3, p4, p5, p6, p7

        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case a1
        case a2
        case b
    }

    package static var spec: TLASpec {
        #spec("SimpleRegular") {
            Extends(.integers)
            Algorithm("SimpleRegular") { scope in
                let x = scope.sharedVar(initial: Function<Process, SetExpr<Int>>.literal(
                    (.p0, SetExpr<Int>.literal(0)), (.p1, SetExpr<Int>.literal(0)),
                    (.p2, SetExpr<Int>.literal(0)), (.p3, SetExpr<Int>.literal(0)),
                    (.p4, SetExpr<Int>.literal(0)), (.p5, SetExpr<Int>.literal(0)),
                    (.p6, SetExpr<Int>.literal(0)), (.p7, SetExpr<Int>.literal(0))
                ))
                let y = scope.sharedVar(initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0), (.p2, 0), (.p3, 0),
                    (.p4, 0), (.p5, 0), (.p6, 0), (.p7, 0)
                ))
                let predecessor = Function<Process, Process>.literal(
                    (.p0, .p7), (.p1, .p0), (.p2, .p1), (.p3, .p2),
                    (.p4, .p3), (.p5, .p4), (.p6, .p5), (.p7, .p6)
                )

                Each(Process.all) { process in
                    Do(Step.a1) {
                        x.set(x.updating(process, to: SetExpr<Int>.literal(0, 1)))
                    }
                    Do(Step.a2) {
                        x.set(x.updating(process, to: SetExpr<Int>.literal(1)))
                    }
                    Do(Step.b) {
                        With(x[predecessor[process]]) { value in
                            y.set(y.updating(process, to: value.expr))
                        }
                    }
                }

                let typeOK = Process.all.allSatisfy { process in
                    !x[process].isEmpty
                        && x[process].isSubset(of: SetExpr<Int>.literal(0, 1))
                        && SetExpr<Int>.literal(0, 1).contains(y[process])
                        && (At(Step.a1, process) || At(Step.a2, process)
                            || At(Step.b, process) || Finished(process))
                }
                Invariant("PCorrect") {
                    !Process.all.allSatisfy { process in Finished(process) }
                        || Process.all.contains { process in y[process] == 1 }
                }
                Invariant("TypeOK") { typeOK }
                Invariant("Inv") {
                    typeOK
                    Process.all.allSatisfy { process in
                        !(At(Step.b, process) || Finished(process))
                            || x[process] == SetExpr<Int>.literal(1)
                    }
                    !Process.all.allSatisfy { process in Finished(process) }
                        || Process.all.contains { process in y[process] == 1 }
                }
            }
            Validation("simpleRegularValidation", label: "SimpleRegular") {}
        }
    }
}

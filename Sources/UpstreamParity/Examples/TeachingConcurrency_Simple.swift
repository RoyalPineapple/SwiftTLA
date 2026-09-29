import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/TeachingConcurrency/Simple.tla, Simple.cfg (N = 5).
@TLAModel
package struct TeachingSimpleN5Model: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case p0, p1, p2, p3, p4

        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable { case a, b }

    package static var spec: TLASpec {
        #spec("Simple") {
            Extends(.integers)
            Algorithm("Simple", scoped: { scope in
                let x = scope.sharedVar(initial: Function<Process, Int>.mapping { _ in 0 })
                let y = scope.sharedVar(initial: Function<Process, Int>.mapping { _ in 0 })
                let predecessor = Function<Process, Process>.literal(
                    (.p0, .p4), (.p1, .p0), (.p2, .p1), (.p3, .p2), (.p4, .p3)
                )

                Each(Process.all) { process in
                    Do(Step.a) {
                        Assign(x, to: x.updating(process, to: 1))
                    }
                    Do(Step.b) {
                        Assign(y, to: y.updating(process, to: x[predecessor[process]]))
                    }
                }

                let typeOK = ForAll(Process.all) { process in
                    SetExpr<Int>.literal(0, 1).contains(x[process])
                        && SetExpr<Int>.literal(0, 1).contains(y[process])
                        && (At(Step.a, process) || At(Step.b, process) || Finished(process))
                }
                Invariant("PCorrect") {
                    !ForAll(Process.all) { process in Finished(process) }
                        || Exists(in: Process.all) { process in y[process] == 1 }
                }
                Invariant("TypeOK") { typeOK }
                Invariant("Inv") {
                    typeOK
                    ForAll(Process.all) { process in
                        !(At(Step.b, process) || Finished(process)) || x[process] == 1
                    }
                    !ForAll(Process.all) { process in Finished(process) }
                        || Exists(in: Process.all) { process in y[process] == 1 }
                }
            })
            Validation("Simple") {}
        }
    }
}

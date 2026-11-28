// Processes arrive at a barrier and are released together.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/barriers/Barrier.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BarrierModel {
    private enum Step: String, CaseIterable {
        case arrive = "b0"
        case release = "b1"
    }

    package static var spec: TLASpec {
        #spec("Barrier") { scope in
            Extends(.integers)
            let N = scope.parameter(as: Int.self, in: Int.all)
            let processes = IntRange(1, through: N)
            let pc = scope.sharedVar(initial: Dictionary<Int, String>.mapping(over: processes) { _ in "b0" })

            Do(Step.arrive, over: processes) { process in
                When(pc[process] == "b0")
                pc[process].set("b1")
            }
            Do(Step.release) {
                When(processes.allSatisfy { process in pc[process] == "b1" })
                pc.set(Dictionary<Int, String>.mapping(over: processes) { _ in "b0" })
            }

            let typeOK = Invariant("TypeOK")
            typeOK {
                pc.keys == processes
                processes.allSatisfy { process in pc[process] == "b0" || pc[process] == "b1" }
            }
            let BarrierProperty = Temporal()
            BarrierProperty(.alwaysStep(on: pc) { before, after in
                processes.allSatisfy { p in
                    processes.allSatisfy { q in
                        before[p] != "b0" || before[q] != "b1" || after[q] == "b1"
                    }
                }
            })

            Validation("APBarrier") { Bind(N, to: 6) }.checking(only: [typeOK])
            Validation("Barrier") { Bind(N, to: 6) }.checking(only: [typeOK, BarrierProperty])
        }
    }
}

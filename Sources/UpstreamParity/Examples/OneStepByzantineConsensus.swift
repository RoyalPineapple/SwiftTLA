// Correct processes propose a bit and decide after receiving a quorum. A process may become Byzantine.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/cf1s-folklore/cf1s_folklore.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct OneStepByzantineConsensusModel: Sendable {
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("cf1s_folklore") { scope in
            let N = scope.parameter(as: Int.self, in: 1...4)
            let T = scope.parameter(as: Int.self, in: 0...1)
            let F = scope.parameter(as: Int.self, in: 0...1)
            Assume(N > 3 * T && T >= F && F >= 0)
            let processes = IntRange(1, through: N)
            let quorum = N - T
            let pc = scope.sharedVar(initiallyIn: Functions(from: processes, to: Set<String>(["V0", "V1"])))
            let nSnt0 = scope.sharedVar(initial: 0)
            let nSnt1 = scope.sharedVar(initial: 0)
            let nSnt0F = scope.sharedVar(initial: 0)
            let nSnt1F = scope.sharedVar(initial: 0)
            let nFaulty = scope.sharedVar(initial: 0)
            let nRcvd0 = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: processes) { _ in 0 })
            let nRcvd1 = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: processes) { _ in 0 })

            Do(Step.next) {
                With(processes) { process in
                    Let(pc[process]) { phase in
                        Either {
                            When(nRcvd0[process] < nSnt0 + nSnt0F) { nRcvd0[process] += 1 }
                            When(nRcvd1[process] < nSnt1 + nSnt1F) { nRcvd1[process] += 1 }
                            When(phase == "V0") {
                                pc[process].set("S0")
                                nSnt0 += 1
                            }
                            When(phase == "V1") {
                                pc[process].set("S1")
                                nSnt1 += 1
                            }
                            When((phase == "S0" || phase == "S1") && nRcvd0[process] + nRcvd1[process] >= quorum) {
                                Either {
                                    When(nRcvd0[process] >= quorum) { pc[process].set("D0") }
                                    When(nRcvd1[process] >= quorum) { pc[process].set("D1") }
                                    When(nRcvd0[process] < quorum && nRcvd1[process] < quorum) {
                                        pc[process].set(If(phase == "S0", then: "U0", else: "U1"))
                                    }
                                }
                            }
                            // With at most one fault, the published V1 branch requires nSnt0F' to be both 0 and 1.
                            When(nFaulty < F && phase != "BYZ" && phase != "V1") {
                                pc[process].set("BYZ")
                                nFaulty += 1
                                nSnt0F.set(If(phase == "V0", then: nSnt0F + 1, else: nSnt0F))
                            }
                            When(true) { Skip() }
                        }
                    }
                }
            }
            // Faulty is the only branch that increments the fault count.
            WeakFairnessNext(preserving: nFaulty)
            let counts = IntRange(0, through: N)
            let phases = Set<String>(["V0", "V1", "S0", "S1", "D0", "D1", "U0", "U1", "BYZ"])
            Invariant("TypeOK") {
                counts.contains(nSnt0) && counts.contains(nSnt1) && counts.contains(nSnt0F) && counts.contains(nSnt1F)
                nFaulty >= 0 && nFaulty <= F
                pc.keys == processes && nRcvd0.keys == processes && nRcvd1.keys == processes
                processes.allSatisfy { process in
                    phases.contains(pc[process]) && counts.contains(nRcvd0[process]) && counts.contains(nRcvd1[process])
                }
            }
            let zeroOnly = processes.allSatisfy { process in
                pc[process] != "U0" && pc[process] != "U1" && pc[process] != "D1"
            }
            let oneOnly = processes.allSatisfy { process in
                pc[process] != "U0" && pc[process] != "U1" && pc[process] != "D0"
            }
            let OneStep0_Ltl = Temporal()
            OneStep0_Ltl(.conditional(processes.allSatisfy { process in pc[process] == "V0" },
                then: .always(zeroOnly), else: .always(true)))
            let OneStep1_Ltl = Temporal()
            OneStep1_Ltl(.conditional(processes.allSatisfy { process in pc[process] == "V1" },
                then: .eventually(oneOnly), else: .always(true)))
            Validation("Upstream") {
                Bind(N, to: 4)
                Bind(T, to: 1)
                Bind(F, to: 1)
            }
        }
    }
}

// Processes vote on a transaction while an unreliable failure detector can suspect a crash.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/nbacg_guer01/nbacg_guer01.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct GuerraouiAtomicCommitModel: Sendable {
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("nbacg_guer01") { scope in
            let N = scope.parameter(as: Int.self, in: Int.all)
            let processes = IntRange(1, through: N)
            let zero = Dictionary<Int, Int>.mapping(over: processes) { _ in 0 }
            let nSntYes = scope.sharedVar(initial: 0)
            let nSntNo = scope.sharedVar(initial: 0)
            let nSntYesF = scope.sharedVar(initial: 0)
            let nSntNoF = scope.sharedVar(initial: 0)
            let nRcvdYes = scope.sharedVar(initial: zero)
            let nRcvdNo = scope.sharedVar(initial: zero)
            let votes = Set<String>(["YES", "NO"])
            let pc: SharedVariable<[Int: String]> = scope.sharedVar(initiallyIn: Functions(from: processes, to: votes))
            let someFail: SharedVariable<[Int: Bool]> = scope.sharedVar(initiallyIn: Functions(from: processes, to: Bool.all))

            Do(Step.next) {
                With(processes) { process in
                    let phase = pc[process]
                    Either {
                        When(phase != "BYZ") {
                            nSntYesF.set(If(phase == "YES", then: nSntYesF + 1, else: nSntYesF))
                            nSntNoF.set(If(phase == "NO", then: nSntNoF + 1, else: nSntNoF))
                            pc[process].set("BYZ")
                        }
                        When(phase == "SENT" && nRcvdYes[process] < nSntYes + nSntYesF) {
                            nRcvdYes[process] += 1
                        }
                        When(phase == "SENT" && nRcvdNo[process] < nSntNo + nSntNoF) {
                            nRcvdNo[process] += 1
                        }
                        When(phase == "YES" && !someFail[process]) {
                            nSntYes += 1
                            pc[process].set("SENT")
                        }
                        When(phase == "NO" && !someFail[process]) {
                            nSntNo += 1
                            pc[process].set("SENT")
                        }
                        When(votes.contains(phase) && someFail[process]) { pc[process].set("ABORT") }
                        When(phase == "SENT" && nRcvdNo[process] > 0) { pc[process].set("ABORT") }
                        When(phase == "SENT" && nRcvdNo[process] == 0 && nRcvdYes[process] >= N) {
                            pc[process].set("COMMIT")
                        }
                        When(true) { Skip() }
                    }
                }
            }

            // Exactly the Crash branch adds a process to this set.
            let crashed = processes.filter { process in pc[process] == "BYZ" }
            WeakFairnessNext(preserving: crashed)
            let counts = IntRange(0, through: N)
            let phases = Set<String>(["YES", "NO", "SENT", "ABORT", "COMMIT", "BYZ"])
            let TypeOK = Invariant()
            TypeOK {
                counts.contains(nSntYes) && counts.contains(nSntNo) && counts.contains(nSntYesF) && counts.contains(nSntNoF)
                Functions(from: processes, to: IntRange(0, through: nSntYes + nSntYesF)).contains(nRcvdYes)
                Functions(from: processes, to: IntRange(0, through: nSntNo + nSntNoF)).contains(nRcvdNo)
                Functions(from: processes, to: phases).contains(pc)
                Functions(from: processes, to: Bool.all).contains(someFail)
            }
            let committed = processes.contains { p in pc[p] == "COMMIT" }
            let aborted = processes.contains { p in pc[p] == "ABORT" }
            let AgrrLtl = Temporal()
            AgrrLtl(.always(!(committed && aborted)))
            let AbortValidityLtl = Temporal()
            AbortValidityLtl(.conditional(processes.contains { p in pc[p] == "NO" }, then: .always(!committed), else: .always(true)))
            let CommitValidityLtl = Temporal()
            CommitValidityLtl(.conditional(processes.allSatisfy { p in pc[p] == "YES" && !someFail[p] },
                then: .always(!aborted), else: .always(true)))
            // ([] healthy) => (<> decided) is equivalent to <> (!healthy || decided).
            let TerminationLtl = Temporal()
            TerminationLtl(.eventually(processes.contains { p in pc[p] == "BYZ" || someFail[p] }
                || processes.allSatisfy { p in pc[p] == "COMMIT" || pc[p] == "ABORT" }))

            Validation("Upstream") { Bind(N, to: 3) }
            Validation("AP") { Bind(N, to: 3) }.checking(only: [TypeOK])
        }
    }
}

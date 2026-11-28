// A process receives messages and a fresh failure-detector reading in the same atomic step.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/nbacc_ray97/nbacc_ray97.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RaynalAtomicCommitModel: Sendable {
    package typealias Message = Pair<Int, String>
    private enum Step: String, CaseIterable { case advance = "Step" }

    package static var spec: TLASpec {
        #spec("nbacc_ray97") { scope in
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N >= 0)
            let processes = IntRange(1, through: N)
            let votes = Set<String>(["YES", "NO"])
            let pc = scope.sharedVar(initiallyIn: Functions(from: processes, to: votes))
            let sent = scope.sharedVar(initial: Set<Message>())
            let rcvd = scope.sharedVar(initial: Dictionary<Int, Set<Message>>.mapping(over: processes) { _ in Set<Message>() })
            let fd: SharedVariable<[Int: Bool]> = scope.sharedVar(initiallyIn: Functions(from: processes, to: Bool.all))

            Do(Step.advance, over: processes) { process in
                Let(pc[process]) { phase in
                    Let(rcvd[process]) { previouslyReceived in
                        With(Bool.all) { suspected in
                            With(Subsets(of: sent)) { incoming in
                                let received = previouslyReceived.union(incoming)
                                Either {
                                    When(phase != "CRASH") { pc[process].set("CRASH") }
                                    When(phase == "YES") {
                                        pc[process].set("SENT")
                                        sent.insert(Pair<Int, String>.literal(process, "YES"))
                                    }
                                    When(phase == "NO") {
                                        pc[process].set("SENT")
                                        sent.insert(Pair<Int, String>.literal(process, "NO"))
                                    }
                                    // A NO vote is read from the old inbox; the YES test uses the new inbox.
                                    When(phase == "SENT" && (suspected || processes.contains { sender in
                                        previouslyReceived.contains(Pair<Int, String>.literal(sender, "NO"))
                                    })) { pc[process].set("ABORT") }
                                    When(phase == "SENT" && !suspected && processes.allSatisfy { sender in
                                        received.contains(Pair<Int, String>.literal(sender, "YES"))
                                    }) { pc[process].set("COMMIT") }
                                    When(true) { Skip() }
                                }
                                rcvd[process].set(received)
                                fd[process].set(suspected)
                            }
                        }
                    }
                }
            }
            let crashed = processes.filter { process in pc[process] == "CRASH" }
            WeakFairnessNext(on: pc, preserving: crashed)

            let messages = processes.mapping { p in Pair<Int, String>.literal(p, "YES") }
                .union(processes.mapping { p in Pair<Int, String>.literal(p, "NO") })
            let phases = Set<String>(["YES", "NO", "SENT", "COMMIT", "ABORT", "CRASH"])
            Invariant("TypeOK") {
                sent.isSubset(of: messages)
                Functions(from: processes, to: phases).contains(pc)
                Functions(from: processes, to: Subsets(of: messages)).contains(rcvd)
                Functions(from: processes, to: Bool.all).contains(fd)
            }
            Validation("Upstream") { Bind(N, to: 2) }
        }
    }
}

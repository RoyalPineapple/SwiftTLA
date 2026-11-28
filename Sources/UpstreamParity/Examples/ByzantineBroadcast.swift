// Correct processes relay ECHO messages after a threshold and accept after a second threshold.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/bcastByz/bcastByz.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ByzantineBroadcastModel: Sendable {
    package typealias Message = Pair<Int, String>
    private enum Step: String, CaseIterable {
        case next = "Next"
    }

    package static var spec: TLASpec {
        #spec("bcastByz") { scope in
            let N = scope.parameter(as: Int.self, in: 1...10)
            let T = scope.parameter(as: Int.self, in: 0...3)
            let F = scope.parameter(as: Int.self, in: 0...3)
            let noBroadcast = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            Assume(N > 3 * T && T >= F && F >= 0)
            let processes = IntRange(1, through: N)
            let Corr = scope.sharedVar(initiallyIn: Subsets(of: processes).filter { members in members.count == N - F })
            let Faulty = scope.sharedVar(initial: processes.subtracting(Corr))
            let initialLabels = If(noBroadcast, then: Set<String>(["V0"]), else: Set<String>(["V0", "V1"]))
            let pc = scope.sharedVar(initiallyIn: Functions(from: processes, to: initialLabels))
            let rcvd = scope.sharedVar(initial: Dictionary<Int, Set<Message>>.mapping(over: processes) { _ in Set<Message>() })
            let sent = scope.sharedVar(initial: Set<Message>())
            let byzantineMessages = Faulty.mapping { p in Pair<Int, String>.literal(p, "ECHO") }

            Do(Step.next) {
                Either {
                    When(true) { Skip() }
                    When(true) {
                        Let(N - 2 * T) { relay in
                            Let(N - T) { accept in
                                With(Corr) { p in
                                    Let(pc[p]) { current in
                                        Let(rcvd[p]) { previouslyReceived in
                                            With(Subsets(of: sent.union(byzantineMessages))) { incoming in
                                                let received = previouslyReceived.union(incoming)
                                                Either {
                                                    When(current == "V1" || (current == "V0" && received.count >= relay && received.count < accept)) {
                                                        rcvd[p].set(received)
                                                        pc[p].set("SE")
                                                        sent.insert(Pair<Int, String>.literal(p, "ECHO"))
                                                    }
                                                    When(current != "AC" && received.count >= accept) {
                                                        rcvd[p].set(received)
                                                        pc[p].set("AC")
                                                        sent.set(If(current == "SE", then: sent, else: sent.inserting(Pair<Int, String>.literal(p, "ECHO"))))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // A delivery can come solely from correct senders exactly when it adds no faulty message.
            let receivedFromFaulty = Dictionary<Int, Set<Message>>.mapping(over: Corr) { receiver in
                rcvd[receiver].intersection(byzantineMessages)
            }
            WeakFairnessNext(preserving: receivedFromFaulty)
            let messages = processes.mapping { p in Pair<Int, String>.literal(p, "ECHO") }
            let TypeOK = Invariant()
            TypeOK {
                pc.keys == processes && processes.allSatisfy { p in Set<String>(["V0", "V1", "SE", "AC"]).contains(pc[p]) }
                Corr.isSubset(of: processes) && Faulty.isSubset(of: processes) && sent.isSubset(of: messages)
                rcvd.keys == processes && processes.allSatisfy { p in rcvd[p].isSubset(of: sent.union(byzantineMessages)) }
            }
            let FCConstraints = Invariant()
            FCConstraints {
                Corr.isSubset(of: processes) && Faulty.isSubset(of: processes)
                Corr.union(Faulty) == processes && Faulty == processes.subtracting(Corr)
                Corr.count >= N - T && Faulty.count <= T
                byzantineMessages.isSubset(of: messages) && byzantineMessages.count == Faulty.count
            }
            let allAccept = Corr.allSatisfy { p in pc[p] == "AC" }
            let someAccept = Corr.contains { p in pc[p] == "AC" }
            let CorrLtl = Temporal()
            CorrLtl(.conditional(Corr.allSatisfy { p in pc[p] == "V1" }, then: .eventually(allAccept), else: .always(true)))
            let RelayLtl = Temporal()
            RelayLtl(.leadsTo(someAccept, allAccept))
            let UnforgLtl = Temporal()
            UnforgLtl(.conditional(Corr.allSatisfy { p in pc[p] == "V0" }, then: .always(!someAccept), else: .always(true)))
            let Unforg = Invariant()
            Unforg { !someAccept }
            Validation("Broadcast") {
                Bind(N, to: 4)
                Bind(T, to: 1)
                Bind(F, to: 1)
                Bind(noBroadcast, to: false)
            }.checking(only: [TypeOK, FCConstraints, CorrLtl, RelayLtl, UnforgLtl])
            Validation("NoBroadcast") {
                Bind(N, to: 10)
                Bind(T, to: 3)
                Bind(F, to: 2)
                Bind(noBroadcast, to: true)
            }.behavior(.initialAndNext).checking(only: [TypeOK, FCConstraints, Unforg, CorrLtl, RelayLtl])
        }
    }
}

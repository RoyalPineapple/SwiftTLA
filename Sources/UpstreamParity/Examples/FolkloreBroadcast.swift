// A process relays ECHO on acceptance. A crash removes that process from the correct set.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/bcastFolklore/bcastFolklore.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct FolkloreBroadcastModel: Sendable {
    package typealias Message = Pair<Int, String>
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("bcastFolklore") { scope in
            let processCount = scope.parameter(tlaName: "N", as: Int.self, in: 4...4)
            let threshold = scope.parameter(tlaName: "T", as: Int.self, in: 1...1)
            let faultLimit = scope.parameter(tlaName: "F", as: Int.self, in: 1...1)
            Assume(processCount > 2 * threshold && threshold >= faultLimit && faultLimit >= 0)
            let processes = IntRange(1, through: processCount)
            let correct = scope.sharedVar(tlaName: "Corr", initial: processes)
            let crashes = scope.sharedVar(tlaName: "nCrashed", initial: 0)
            let pc = scope.sharedVar(initiallyIn: Functions(from: processes, to: Set<String>(["V0", "V1"])))
            let received = scope.sharedVar(tlaName: "rcvd", initial: Dictionary<Int, Set<Message>>.mapping(over: processes) { _ in Set<Message>() })
            let sent = scope.sharedVar(initial: Set<Message>())

            Do(Step.next) {
                With(correct) { process in
                    When(pc[process] != "CR")
                    With(Subsets(of: sent)) { delivery in
                        When(received[process].isSubset(of: delivery))
                        received[process].set(delivery)
                        Either {
                            When(pc[process] == "V1") {
                                pc[process].set("AC")
                                sent.insert(Pair<Int, String>.literal(process, "ECHO"))
                            }
                            When((pc[process] == "V0" || pc[process] == "V1") && !delivery.isEmpty) {
                                pc[process].set("AC")
                                sent.insert(Pair<Int, String>.literal(process, "ECHO"))
                            }
                            When(crashes < faultLimit) {
                                crashes += 1
                                pc[process].set("CR")
                                correct.remove(process)
                            }
                            When(true) { Skip() }
                        }
                    }
                }
            }
            WeakFairnessNext(preserving: crashes)
            let messages = processes.mapping { p in Pair<Int, String>.literal(p, "ECHO") }
            let typeOK = Invariant("TypeOK")
            typeOK {
                sent.isSubset(of: messages)
                pc.keys == processes && processes.allSatisfy { p in Set<String>(["V0", "V1", "AC", "CR"]).contains(pc[p]) }
                received.keys == processes && processes.allSatisfy { p in received[p].isSubset(of: messages) }
                IntRange(0, through: processCount).contains(crashes)
                correct.isSubset(of: processes)
            }
            let accepted = correct.contains { p in pc[p] == "AC" }
            let allAccepted = correct.allSatisfy { p in pc[p] == "AC" }
            let UnforgLtl = Temporal()
            UnforgLtl(.conditional(correct.allSatisfy { p in pc[p] == "V0" },
                                   then: .always(!accepted), else: .always(true)))
            let CorrLtl = Temporal()
            CorrLtl(.conditional(correct.allSatisfy { p in pc[p] == "V1" },
                                 then: .eventually(accepted), else: .always(true)))
            let RelayLtl = Temporal()
            RelayLtl(.leadsTo(accepted, allAccepted))
            // An unsent ECHO witnesses the published existential immediately. Once all are sent,
            // delivery to every correct process is permanent: received sets grow and correct only shrinks.
            let allSent = messages.isSubset(of: sent)
            let oneDeliveredToAll = messages.contains { message in
                correct.allSatisfy { p in received[p].contains(message) }
            }
            let ReliableChan = Temporal()
            ReliableChan(.leadsTo(allSent, oneDeliveredToAll))
            Validation("Apalache") {
                Bind(processCount, to: 4)
                Bind(threshold, to: 1)
                Bind(faultLimit, to: 1)
            }.checking(only: [typeOK])
            Validation("Upstream") {
                Bind(processCount, to: 4)
                Bind(threshold, to: 1)
                Bind(faultLimit, to: 1)
            }
        }
    }
}

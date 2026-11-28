// Ring processes forward candidate identifiers until a process recognizes its own and becomes
// leader.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/chang_roberts/ChangRoberts.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/chang_roberts/ChangRoberts.tla.
@TLAModel
package struct ChangRobertsModel: Sendable {
    package enum ProcessState: String, CaseIterable, FiniteTLAValueDomain {
        case candidate = "cand"
        case lost
        case won

        package static var defaultValue: Self { .candidate }
        package static let finiteValues = allCases
    }

    private enum Step: String, CaseIterable {
        case sendIDIfInitiator = "n0"
        case processIncomingID = "n1"
    }

    package static var spec: TLASpec {
        #spec("ChangRoberts") { model in
            Extends(.naturals, .sequences)
            let nodeCount = model.parameter(tlaName: "N", as: Int.self, in: Int.all)
            let nodeIDs = model.parameter(tlaName: "Id", as: [Int].self, in: Sequences(of: Int.all))
            let nodes = IntRange(1, through: nodeCount)
            Assume(nodeCount > 0 && nodeIDs.count == nodeCount
                && nodes.allSatisfy { node in nodeIDs[node] >= 0
                    && nodes.allSatisfy { other in node == other || nodeIDs[node] != nodeIDs[other] }
                })
            let TypeOK = Invariant()
            let Correctness = Invariant()
            let Liveness = Temporal()

            Algorithm("ChangRoberts") { scope in
                let messages = scope.sharedVar(tlaName: "msgs", initial: Dictionary<Int, Set<Int>>.mapping(over: nodes) { _ in Set<Int>() })
                let initiator: SharedVariable<[Int: Bool]> = scope.sharedVar(initiallyIn:
                    Functions(from: nodes, to: Bool.all))
                let state = scope.sharedVar(initial: Dictionary<Int, ProcessState>.mapping(over: nodes) { node in
                    If(initiator[node], then: ProcessState.candidate, else: ProcessState.lost)
                })

                Each(nodes, fairness: .weak) { node in
                    let successor = If(node == nodeCount, then: 1, else: node + 1)
                    Do(Step.sendIDIfInitiator) {
                        If(initiator[node]) {
                            messages[successor].set(messages[successor].inserting(nodeIDs[node]))
                        }
                    }
                    Loop(Step.processIncomingID) {
                        With(messages[node]) { candidate in
                            messages[node].set(messages[node].removing(candidate))
                            If(state[node] == ProcessState.lost || candidate < nodeIDs[node]) {
                                messages[successor].set(messages[successor].inserting(candidate))
                                If(state[node] != ProcessState.lost) {
                                    state[node].set(ProcessState.lost)
                                }
                            } else: {
                                If(candidate == nodeIDs[node]) {
                                    state[node].set(ProcessState.won)
                                }
                            }
                        }
                    }
                }

                TypeOK {
                    messages.keys == nodes && initiator.keys == nodes && state.keys == nodes
                    nodes.allSatisfy { node in
                        Set<ProcessState>([.candidate, .lost, .won]).contains(state[node])
                            && messages[node].allSatisfy { message in
                                nodes.contains { owner in message == nodeIDs[owner] }
                            }
                    }
                }
                Correctness {
                    nodes.allSatisfy { node in
                        state[node] != ProcessState.won || (initiator[node]
                            && nodes.allSatisfy { other in
                                other == node || (state[other] == ProcessState.lost
                                    && (!initiator[other] || nodeIDs[other] > nodeIDs[node]))
                            })
                    }
                }
                let hasCandidate = nodes.contains { node in state[node] == ProcessState.candidate }
                let hasWinner = nodes.contains { node in state[node] == ProcessState.won }
                Liveness(.conditional(hasCandidate, then: .eventually(hasWinner), else: .always(true)))
            }

            Validation("MCChangRoberts") {
                Bind(nodeCount, to: 3)
                Bind(nodeIDs, to: [1, 2, 3])
            }.checkingDeadlock(false)
            Validation("APChangRoberts") {
                Bind(nodeCount, to: 3)
                Bind(nodeIDs, to: [3, 1, 2])
            }.behavior(.initialAndNext).checking(only: [TypeOK, Correctness]).checkingDeadlock(false)
        }
    }
}

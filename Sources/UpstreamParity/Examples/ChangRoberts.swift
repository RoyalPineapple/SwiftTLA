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

    private enum Step: String, CaseIterable { case n0, n1 }

    package static var spec: TLASpec {
        #spec("ChangRoberts") { model in
            Extends(.naturals, .sequences)
            let N = model.parameter(as: Int.self, in: Int.all)
            let Id = model.parameter(as: [Int].self, in: Sequences(of: Int.all))
            let Node = IntRange(1, through: N)
            Assume(N > 0 && Id.count == N
                && Node.allSatisfy { node in Id[node] >= 0
                    && Node.allSatisfy { other in node == other || Id[node] != Id[other] }
                })
            let TypeOK = Invariant()
            let Correctness = Invariant()
            let Liveness = Temporal()

            let ChangRoberts = Algorithm { scope in
                let msgs = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: Node) { _ in Set<Int>() })
                let initiator: SharedVariable<[Int: Bool]> = scope.sharedVar(initiallyIn:
                    Functions(from: Node, to: Bool.all))
                let state = scope.sharedVar(initial: Dictionary<Int, ProcessState>.mapping(over: Node) { node in
                    If(initiator[node], then: ProcessState.candidate, else: ProcessState.lost)
                })

                Each(Node, fairness: .weak) { node in
                    let successor = If(node == N, then: 1, else: node + 1)
                    Do(Step.n0) {
                        If(initiator[node]) {
                            msgs[successor].set(msgs[successor].inserting(Id[node]))
                        }
                    }
                    Loop(Step.n1) {
                        With(msgs[node]) { candidate in
                            msgs[node].set(msgs[node].removing(candidate))
                            If(state[node] == ProcessState.lost || candidate < Id[node]) {
                                msgs[successor].set(msgs[successor].inserting(candidate))
                                If(state[node] != ProcessState.lost) {
                                    state[node].set(ProcessState.lost)
                                }
                            } else: {
                                If(candidate == Id[node]) {
                                    state[node].set(ProcessState.won)
                                }
                            }
                        }
                    }
                }

                TypeOK {
                    msgs.keys == Node && initiator.keys == Node && state.keys == Node
                    Node.allSatisfy { node in
                        Set<ProcessState>([.candidate, .lost, .won]).contains(state[node])
                            && msgs[node].allSatisfy { message in
                                Node.contains { owner in message == Id[owner] }
                            }
                    }
                }
                Correctness {
                    Node.allSatisfy { node in
                        state[node] != ProcessState.won || (initiator[node]
                            && Node.allSatisfy { other in
                                other == node || (state[other] == ProcessState.lost
                                    && (!initiator[other] || Id[other] > Id[node]))
                            })
                    }
                }
                let hasCandidate = Node.contains { node in state[node] == ProcessState.candidate }
                let hasWinner = Node.contains { node in state[node] == ProcessState.won }
                Liveness(.conditional(hasCandidate, then: .eventually(hasWinner), else: .always(true)))
            }
            ChangRoberts

            Validation("MCChangRoberts") {
                Bind(N, to: 3)
                Bind(Id, to: [1, 2, 3])
            }.checkingDeadlock(false)
            Validation("APChangRoberts") {
                Bind(N, to: 3)
                Bind(Id, to: [3, 1, 2])
            }.behavior(.initialAndNext).checking(only: [TypeOK, Correctness]).checkingDeadlock(false)
        }
    }
}

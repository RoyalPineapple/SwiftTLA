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
                && ForAll(in: Node) { node in Id[node] >= 0
                    && ForAll(in: Node) { other in node == other || Id[node] != Id[other] }
                })
            let TypeOK = Invariant()
            let Correctness = Invariant()
            let Liveness = Temporal()

            let ChangRoberts = Algorithm(scoped: { scope in
                let msgs = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: Node) { _ in Set<Int>() })
                let initiator: SharedVariable<[Int: Bool]> = scope.sharedVar(in:
                    Functions(from: Node, to: Set<Bool>([false, true])))
                let state = scope.sharedVar(initial: Dictionary<Int, ProcessState>.mapping(over: Node) { node in
                    If(initiator[node], then: ProcessState.candidate, else: ProcessState.lost)
                })

                Each(Node, fairness: .weak) { node in
                    let successor = If(node == N, then: 1, else: node + 1)
                    Do(Step.n0) {
                        If(initiator[node]) {
                            Assign(msgs[successor], to: msgs[successor].inserting(Id[node]))
                        }
                    }
                    While(Step.n1, true) {
                        With(msgs[node]) { candidate in
                            Assign(msgs[node], to: msgs[node].removing(candidate))
                            If(state[node] == ProcessState.lost || candidate < Id[node]) {
                                Assign(msgs[successor], to: msgs[successor].inserting(candidate))
                                If(state[node] != ProcessState.lost) {
                                    Assign(state[node], to: ProcessState.lost)
                                }
                            } else: {
                                If(candidate == Id[node]) {
                                    Assign(state[node], to: ProcessState.won)
                                }
                            }
                        }
                    }
                }

                TypeOK {
                    msgs.keys == Node && initiator.keys == Node && state.keys == Node
                    ForAll(in: Node) { node in
                        Set<ProcessState>([.candidate, .lost, .won]).contains(state[node])
                            && ForAll(in: msgs[node]) { message in
                                Exists(in: Node) { owner in message == Id[owner] }
                            }
                    }
                }
                Correctness {
                    ForAll(in: Node) { node in
                        state[node] != ProcessState.won || (initiator[node]
                            && ForAll(in: Node) { other in
                                other == node || (state[other] == ProcessState.lost
                                    && (!initiator[other] || Id[other] > Id[node]))
                            })
                    }
                }
                let hasCandidate = Exists(in: Node) { node in state[node] == ProcessState.candidate }
                let hasWinner = Exists(in: Node) { node in state[node] == ProcessState.won }
                Liveness(.conditional(hasCandidate, then: .eventually(hasWinner), else: .always(true)))
            })
            ChangRoberts

            let MCChangRoberts = Validation {
                Bind(N, to: 3)
                Bind(Id, to: [1, 2, 3])
            }.checkingDeadlock(false)
            MCChangRoberts
            let APChangRoberts = Validation {
                Bind(N, to: 3)
                Bind(Id, to: [3, 1, 2])
            }.behavior(.initialAndNext).checking(only: [TypeOK, Correctness]).checkingDeadlock(false)
            APChangRoberts
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardestParallelModel: Sendable {
    package enum Step: String, CaseIterable {
        case nextParallel = "NextParallel"
        case nextParallelFreeze = "NextParallelFreeze"
    }

    package static var spec: TLASpec {
        #spec("DieHardestParallel") { scope in
            Extends(.naturals)
            let Capacities = scope.parameter(as: [[String: Int]].self,
                in: Set<[[String: Int]]>([[["j1": 9, "j2": 10], ["j1": 1, "j2": 3]]]))
            let Goal = scope.parameter(as: Int.self, in: Set<Int>([2]))
            let Freeze = scope.parameter(as: Bool.self)
            let c1 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[1].keys) { _ in 0 })
            let c2 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[2].keys) { _ in 0 })
            let s1 = scope.sharedVar(initial: 0)
            let s2 = scope.sharedVar(initial: 0)

            let firstStep = Macro {
                With(Capacities[1].keys, Set<Int>([0, 1, 2])) { j, operation in
                    If(operation == 0) {
                        c1[j].set(Capacities[1][j])
                    } else: {
                        If(operation == 1) {
                            c1[j].set(0)
                        } else: {
                            With(Capacities[1].keys) { k in
                                When(j != k)
                                If(c1[j] < Capacities[1][k] - c1[k]) {
                                    let amount = c1[j]
                                    c1[j].set(0)
                                    c1[k] += amount
                                } else: {
                                    let amount = Capacities[1][k] - c1[k]
                                    c1[j].set(c1[j] - amount)
                                    c1[k].set(Capacities[1][k])
                                }
                            }
                        }
                    }
                }
            }
            let secondStep = Macro {
                With(Capacities[2].keys, Set<Int>([0, 1, 2])) { j, operation in
                    If(operation == 0) {
                        c2[j].set(Capacities[2][j])
                    } else: {
                        If(operation == 1) {
                            c2[j].set(0)
                        } else: {
                            With(Capacities[2].keys) { k in
                                When(j != k)
                                If(c2[j] < Capacities[2][k] - c2[k]) {
                                    let amount = c2[j]
                                    c2[j].set(0)
                                    c2[k] += amount
                                } else: {
                                    let amount = Capacities[2][k] - c2[k]
                                    c2[j].set(c2[j] - amount)
                                    c2[k].set(Capacities[2][k])
                                }
                            }
                        }
                    }
                }
            }
            Do(Step.nextParallel, when: !Freeze) {
                firstStep()
                secondStep()
                s1.set(s1)
                s2.set(s2)
            }
            Do(Step.nextParallelFreeze, when: Freeze) {
                If(c1.keys.contains { j in c1[j] == Goal }) {
                    c1.set(c1)
                } else: { firstStep() }
                If(c2.keys.contains { j in c2[j] == Goal }) {
                    c2.set(c2)
                } else: { secondStep() }
                s1.set(s1)
                s2.set(s2)
            }
            let notSolved = Invariant("NotSolved")
            notSolved {
                !(c1.keys.contains { j in c1[j] == Goal }
                    && c2.keys.contains { j in c2[j] == Goal })
            }
            Validation("NextParallel") {
                Bind(Capacities, to: [["j1": 9, "j2": 10], ["j1": 1, "j2": 3]])
                Bind(Goal, to: 2)
                Bind(Freeze, to: false)
            }.expect(notSolved, .violated)
            Validation("NextParallelFreeze") {
                Bind(Capacities, to: [["j1": 9, "j2": 10], ["j1": 1, "j2": 3]])
                Bind(Goal, to: 2)
                Bind(Freeze, to: true)
            }.expect(notSolved, .violated)
        }
    }
}

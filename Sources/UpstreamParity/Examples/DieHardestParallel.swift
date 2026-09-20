import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardestParallelModel: Sendable {
    package enum Step: String, CaseIterable { case NextParallel, NextParallelFreeze }

    package static var spec: TLASpec {
        #spec("DieHardestParallel") { scope in
            Extends(.naturals)
            let Capacities = scope.parameter(as: [[String: Int]].self,
                in: Set<[[String: Int]]>([[["j1": 9, "j2": 10], ["j1": 1, "j2": 3]]]))
            let Goal = scope.parameter(as: Int.self, in: Set<Int>([2]))
            let Freeze = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            let c1 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[1].keys) { _ in 0 })
            let c2 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[2].keys) { _ in 0 })
            let s1 = scope.sharedVar(initial: 0)
            let s2 = scope.sharedVar(initial: 0)
            let NotSolved = Invariant()

            let firstStep = Macro {
                With(Capacities[1].keys, Set<Int>([0, 1, 2])) { j, operation in
                    If(operation == 0) {
                        Assign(c1[j], to: Capacities[1][j])
                    } else: {
                        If(operation == 1) {
                            Assign(c1[j], to: 0)
                        } else: {
                            With(Capacities[1].keys) { k in
                                When(j != k)
                                If(c1[j] < Capacities[1][k] - c1[k]) {
                                    let amount = c1[j]
                                    Assign(c1[j], to: 0)
                                    Assign(c1[k], to: c1[k] + amount)
                                } else: {
                                    let amount = Capacities[1][k] - c1[k]
                                    Assign(c1[j], to: c1[j] - amount)
                                    Assign(c1[k], to: Capacities[1][k])
                                }
                            }
                        }
                    }
                }
            }
            let secondStep = Macro {
                With(Capacities[2].keys, Set<Int>([0, 1, 2])) { j, operation in
                    If(operation == 0) {
                        Assign(c2[j], to: Capacities[2][j])
                    } else: {
                        If(operation == 1) {
                            Assign(c2[j], to: 0)
                        } else: {
                            With(Capacities[2].keys) { k in
                                When(j != k)
                                If(c2[j] < Capacities[2][k] - c2[k]) {
                                    let amount = c2[j]
                                    Assign(c2[j], to: 0)
                                    Assign(c2[k], to: c2[k] + amount)
                                } else: {
                                    let amount = Capacities[2][k] - c2[k]
                                    Assign(c2[j], to: c2[j] - amount)
                                    Assign(c2[k], to: Capacities[2][k])
                                }
                            }
                        }
                    }
                }
            }
            Do(Step.NextParallel, when: !Freeze) {
                firstStep()
                secondStep()
                Assign(s1, to: s1)
                Assign(s2, to: s2)
            }
            Do(Step.NextParallelFreeze, when: Freeze) {
                If(Exists(in: c1.keys) { j in c1[j] == Goal }) {
                    Assign(c1, to: c1)
                } else: { firstStep() }
                If(Exists(in: c2.keys) { j in c2[j] == Goal }) {
                    Assign(c2, to: c2)
                } else: { secondStep() }
                Assign(s1, to: s1)
                Assign(s2, to: s2)
            }
            NotSolved {
                !(Exists(in: c1.keys) { j in c1[j] == Goal }
                    && Exists(in: c2.keys) { j in c2[j] == Goal })
            }
            Validation("NextParallel") {
                Bind(Capacities, to: [["j1": 9, "j2": 10], ["j1": 1, "j2": 3]])
                Bind(Goal, to: 2)
                Bind(Freeze, to: false)
            }.expect(NotSolved, .violated)
            Validation("NextParallelFreeze") {
                Bind(Capacities, to: [["j1": 9, "j2": 10], ["j1": 1, "j2": 3]])
                Bind(Goal, to: 2)
                Bind(Freeze, to: true)
            }.expect(NotSolved, .violated)
        }
    }
}

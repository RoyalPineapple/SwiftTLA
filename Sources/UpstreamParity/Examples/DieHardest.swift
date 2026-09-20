import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardestModel: Sendable {
    package enum Step: String, CaseIterable { case NextInterleaved }

    package static var spec: TLASpec {
        #spec("DieHardest") { scope in
            Extends(.naturals)
            let Capacities = scope.parameter(as: [[String: Int]].self,
                in: Set<[[String: Int]]>([[["j1": 5, "j2": 3], ["j1": 5, "j2": 3, "j3": 3]]]))
            let Goal = scope.parameter(as: Int.self, in: Set<Int>([4]))
            let c1 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[1].keys) { _ in 0 })
            let c2 = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Capacities[2].keys) { _ in 0 })
            let s1 = scope.sharedVar(initial: 0)
            let s2 = scope.sharedVar(initial: 0)
            let NotSolved = Invariant()

            Do(Step.NextInterleaved) {
                With(Set<Int>([1, 2]), Set<Int>([0, 1, 2])) { copy, operation in
                    If(copy == 1) {
                        With(Capacities[1].keys) { j in
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
                        Assign(s1, to: s1 + 1)
                    } else: {
                        With(Capacities[2].keys) { j in
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
                        Assign(s2, to: s2 + 1)
                    }
                }
            }
            NotSolved {
                !(Exists(in: c1.keys) { j in c1[j] == Goal }
                    && Exists(in: c2.keys) { j in c2[j] == Goal })
            }
            Validation("MCDieHardest") {
                Bind(Capacities, to: [["j1": 5, "j2": 3], ["j1": 5, "j2": 3, "j3": 3]])
                Bind(Goal, to: 4)
            }.expect(NotSolved, .violated)
        }
    }
}

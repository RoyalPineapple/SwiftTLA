import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ProcessFairnessExemptionModel: Sendable {
    enum Step: String, CaseIterable { case ncs, cs, missing }

    static var spec: TLASpec {
        #spec("ProcessFairnessExemption") { scope in
            let entered = scope.sharedVar(initial: false)
            let Entered = Temporal()
            Entered(.eventually(entered))
            let processFairnessExemption = Algorithm(label: "ProcessFairnessExemption") {
                Each(Set<Int>([0]), fairness: .weak(excluding: [Step.ncs])) { member in
                    While(Step.ncs, true) { Goto(Step.cs) }
                    Do(Step.cs) {
                        Assign(entered, to: member == 0)
                        Goto(Step.ncs)
                    }
                }
            }
            processFairnessExemption
        }
    }
}

@TLAModel
struct ProcessFairnessGroupModel: Sendable {
    enum Step: String, CaseIterable { case first, second }

    static var spec: TLASpec {
        #spec("ProcessFairnessGroup") { scope in
            let count = scope.sharedVar(initial: 0)
            let processFairnessGroup = Algorithm(label: "ProcessFairnessGroup") {
                Each(Set<Int>([0]), fairness: .weak) { _ in
                    Do(Step.first) { Assign(count, to: count + 1) }
                    Do(Step.second) {
                        Assign(count, to: count + 1)
                        Goto(Step.first)
                    }
                }
            }
            processFairnessGroup
        }
    }
}

@TLAModel
struct ScenarioFairnessSelectionModel: Sendable {
    enum Step: String, CaseIterable { case ncs, cs }

    static var spec: TLASpec {
        #spec("ScenarioFairnessSelection") { scope in
            let entered = scope.sharedVar(initial: false)
            let Entered = Temporal()
            let algorithm = Algorithm(label: "ScenarioFairnessSelection") {
                Each(Set<Int>([0]), fairness: .weak) { _ in
                    Do(Step.ncs) { Goto(Step.cs) }
                    Do(Step.cs) {
                        Assign(entered, to: true)
                        Goto(Step.ncs)
                    }
                }
            }
            algorithm
            Entered(.eventually(entered))
            let mayWait = FairnessProfile(excluding: [Step.ncs])
            mayWait
            let strict = Validation {}.checking(only: [Entered]).checkingDeadlock(false)
            strict
            let relaxed = Validation {}.usingFairness(mayWait).checking(only: [Entered])
                .checkingDeadlock(false).expect(Entered, .violated)
            relaxed
        }
    }
}

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

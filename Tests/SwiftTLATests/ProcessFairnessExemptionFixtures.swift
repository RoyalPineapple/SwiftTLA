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
            Algorithm("ProcessFairnessExemption") {
                Each(Set<Int>([0]), fairness: .weak(excluding: [Step.ncs])) { member in
                    While(Step.ncs, true) { Goto(Step.cs) }
                    Do(Step.cs) {
                        Assign(entered, to: member == 0)
                        Goto(Step.ncs)
                    }
                }
            }
        }
    }
}

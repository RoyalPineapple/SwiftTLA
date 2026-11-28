// This inductive check starts from any permitted consensus state with at most one chosen value.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Paxos/MCConsensus.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PaxosInductiveConsensusModel: Sendable {
    private enum Step: String, CaseIterable { case choose = "Next" }

    package static var spec: TLASpec {
        #spec("MCConsensus") { scope in
            Extends(.finiteSets)
            let values = scope.parameter(tlaName: "Value", as: Set<String>.self, in: Set<Set<String>>([Set(["a", "b", "c"])]))
            Assume(!values.isEmpty)
            let chosen = scope.sharedVar(initiallyIn: Subsets(of: values).filter { subset in subset.count <= 1 })
            Do(Step.choose) {
                When(chosen.isEmpty)
                With(values) { value in chosen.insert(value) }
            }
            Invariant("Inv") {
                chosen.isSubset(of: values)
                chosen.count <= 1
            }
            Validation("published") {
                Bind(values, to: Set<String>(["a", "b", "c"]))
            }.checkingDeadlock(false)
        }
    }
}

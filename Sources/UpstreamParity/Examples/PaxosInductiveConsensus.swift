import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PaxosInductiveConsensusModel: Sendable {
    private enum Step: String, CaseIterable { case choose = "Next" }

    package static var spec: TLASpec {
        #spec("MCConsensus") { scope in
            Extends(.finiteSets)
            let Value = scope.parameter(as: Set<String>.self, in: Set<Set<String>>([Set(["a", "b", "c"])]))
            Assume(!Value.isEmpty)
            let chosen = scope.sharedVar(initiallyIn: Subsets(of: Value).filter { subset in subset.count <= 1 })
            Do(Step.choose) {
                When(chosen.isEmpty)
                With(Value) { value in chosen.insert(value) }
            }
            Invariant("Inv") {
                chosen.isSubset(of: Value)
                chosen.count <= 1
            }
            Validation("published") {
                Bind(Value, to: Set<String>(["a", "b", "c"]))
            }.checkingDeadlock(false)
        }
    }
}

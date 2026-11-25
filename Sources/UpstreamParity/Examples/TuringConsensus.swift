import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TuringConsensusModel: Sendable {
    package enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case a, b, c
        package static var defaultValue: Self { .a }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable { case choose = "Next" }

    package static var spec: TLASpec {
        #spec("TuringConsensus") { scope in
            Extends(.finiteSets)
            let Value = scope.parameter(as: Set<Choice>.self, in: Set<Set<Choice>>([Set([.a, .b, .c])]))
            let chosen = scope.sharedVar(initial: Set<Choice>())
            Do(Step.choose, when: chosen.isEmpty) {
                With(Value) { value in chosen.insert(value) }
            }
            Invariant("Inv") {
                chosen.isSubset(of: Value)
                chosen.count <= 1
            }
            Validation("published") {
                Bind(Value, to: Set<Choice>([.a, .b, .c]))
            }.checkingDeadlock(false)
        }
    }
}

// The consensus specification records the value chosen by the protocol.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/PaxosHowToWinATuringAward/Consensus.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TuringConsensusModel: Sendable {
    package enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case a, b, c, v1, v2
        package static var defaultValue: Self { .a }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable { case choose = "Next" }

    package static var spec: TLASpec {
        #spec("TuringConsensus") { scope in
            Extends(.finiteSets)
            let Value = scope.parameter(as: Set<Choice>.self, in: Set<Set<Choice>>([Set([.a, .b, .c]), Set([.v1, .v2]), Set([.v1])]))
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

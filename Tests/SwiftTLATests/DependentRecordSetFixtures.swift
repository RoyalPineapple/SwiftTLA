import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DependentRecordSetModel {
    struct Pair: Hashable, Sendable { let first: Int; let second: Int }
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("DependentRecordSetModel") { scope in
            let maximum = scope.parameter(as: Int.self, in: 0...4)
            let pair = scope.sharedVar(in: IntRange(0, through: maximum).flatMapping { first in
                IntRange(0, through: first).mapping { second in
                    Pair.expression(first: first, second: second)
                }
            }.filtering { pair in pair.first + pair.second <= maximum })
            Do(Step.stay) { Assign(pair, to: pair) }
            Validation("Zero") { Bind(maximum, to: 0) }
            Validation("Four") { Bind(maximum, to: 4) }
        }
    }
}

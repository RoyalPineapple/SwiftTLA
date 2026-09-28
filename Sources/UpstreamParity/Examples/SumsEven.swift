import SwiftTLA
import SwiftTLAMacros

/// The published MC_sums_even configuration checks a theorem as an assumption.
@TLAModel
package struct SumsEvenModel: Sendable {
    package static var spec: TLASpec {
        #spec("MC_sums_even") { scope in
            Extends(.naturals)
            let MaxNat = scope.parameter(as: Int.self, in: 0...1_000_000)
            Assume(MaxNat >= 0 && ForAll(in: IntRange(0, through: MaxNat)) { x in
                (x.expr + x.expr) % 2 == 0
            })
            Validation("MC_sums_even") {
                Bind(MaxNat, to: 1_000_000)
            }.checkingDeadlock(false)
        }
    }
}

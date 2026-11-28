// The configured check doubles each natural number in a finite range and checks that the result
// is even.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/sums_even/sums_even.tla

import SwiftTLA
import SwiftTLAMacros

/// The published MC_sums_even configuration checks a theorem as an assumption.
@TLAModel
package struct SumsEvenModel: Sendable {
    package static var spec: TLASpec {
        #spec("MC_sums_even") { scope in
            Extends(.naturals)
            let MaxNat = scope.parameter(as: Int.self, in: 0...1_000_000)
            Assume(MaxNat >= 0 && IntRange(0, through: MaxNat).allSatisfy { x in
                (x.expr + x.expr) % 2 == 0
            })
            Validation("MC_sums_even") {
                Bind(MaxNat, to: 1_000_000)
            }.checkingDeadlock(false)
        }
    }
}

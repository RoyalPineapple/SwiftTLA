import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct AssumptionOnlyFixture: Sendable {
    static var spec: TLASpec {
        #spec("AssumptionOnlyFixture") { scope in
            let limit = scope.parameter(as: Int.self, in: 0...3)
            Assume(limit % 2 == 0)
            Validation("even") { Bind(limit, to: 2) }.checkingDeadlock(false)
            Validation("odd") { Bind(limit, to: 3) }.checkingDeadlock(false)
        }
    }
}

@TLAModel
struct PrintedAssumptionFixture: Sendable {
    static var spec: TLASpec {
        #spec("PrintedAssumptionFixture") { scope in
            Extends(.tlc)
            let limit = scope.parameter(as: Int.self, in: 0...3)
            Assume((limit == 2 && PrintT(limit)) || PrintT("No solution"))
            Validation("solution") { Bind(limit, to: 2) }.checkingDeadlock(false)
            Validation("fallback") { Bind(limit, to: 3) }.checkingDeadlock(false)
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SignedDivisionOutputModel: Sendable {
    enum Step: String, CaseIterable { case divide, formalDivide, integerDivide, zeroDivide, overflowDivide, formalLocal, rawLocal }

    static var spec: TLASpec {
        #spec("SignedDivisionOutputModel") { scope in
            let quotient = scope.sharedVar(initial: 0)
            Do(Step.divide) {
                Assign(quotient, to: 5 / -2)
            }
            Do(Step.formalDivide) {
                Assign(quotient, to: Expr<Int>(5) / -2)
            }
            Do(Step.integerDivide) {
                Assign(quotient, to: Expr<Int>(5).integerDivided(by: -2))
            }
            Do(Step.formalLocal) {
                let value: Expr<Int> = 5 / -2
                Assign(quotient, to: value)
            }
            Do(Step.rawLocal) {
                let value: Int = 5 / -2
                Assign(quotient, to: value)
            }
            Do(Step.zeroDivide) {
                Assign(quotient, to: Expr<Int>(5) / 0)
            }
            Do(Step.overflowDivide) {
                Assign(quotient, to: Expr<Int>(Int.min) / -1)
            }
        }
    }
}

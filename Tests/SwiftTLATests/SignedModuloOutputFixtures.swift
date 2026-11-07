import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SignedModuloOutputModel: Sendable {
    enum Step: String, CaseIterable { case modulo, literalModulo, negativeModulo, zeroModulo }

    static var spec: TLASpec {
        #spec("SignedModuloOutputModel") { scope in
            let dividend = scope.sharedVar(initial: -5)
            let remainder = scope.sharedVar(initial: 0)
            Do(Step.modulo) {
                Assign(remainder, to: dividend % 2)
            }
            Do(Step.literalModulo) {
                Assign(remainder, to: Expr<Int>(-5) % 2)
            }
            Do(Step.negativeModulo) {
                Assign(remainder, to: Expr<Int>(3) % -2)
            }
            Do(Step.zeroModulo) {
                Assign(remainder, to: Expr<Int>(3) % 0)
            }
        }
    }
}

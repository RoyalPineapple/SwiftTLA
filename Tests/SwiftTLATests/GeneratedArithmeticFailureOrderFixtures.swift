import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedArithmeticFailureOrderModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("GeneratedArithmeticFailureOrderModel") { scope in
            let numerator = scope.sharedVar(initial: 9_223_372_036_854_775_807)
            let divisor = scope.sharedVar(initial: 0)
            let quotient = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                Assign(quotient, to: (numerator + 1) / (1 / divisor))
            }
        }
    }
}

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

@TLAModel
struct GeneratedNegativeModuloFailureModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("GeneratedNegativeModuloFailureModel") { scope in
            let dividend = scope.sharedVar(initial: -7)
            let divisor = scope.sharedVar(initial: -1)
            let remainder = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                Assign(remainder, to: dividend % divisor)
            }
        }
    }
}

@TLAModel
struct GeneratedMembershipFailureOrderModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("GeneratedMembershipFailureOrderModel") { scope in
            let numerator = scope.sharedVar(initial: 9_223_372_036_854_775_807)
            let divisor = scope.sharedVar(initial: 0)
            let found = scope.sharedVar(initial: false)
            Do(Step.compute) {
                Assign(found, to: SetExpr<Int>.literal(1 / divisor).contains(numerator + 1))
            }
        }
    }
}

@TLAModel
struct GeneratedTupleFailureOrderModel: Sendable {
    enum Step: String, CaseIterable { case compute, overflow }

    static var spec: TLASpec {
        #spec("GeneratedTupleFailureOrderModel") { scope in
            let numerator = scope.sharedVar(initial: 9_223_372_036_854_775_807)
            let divisor = scope.sharedVar(initial: 0)
            let result = scope.sharedVar(initial: TupleExpr<Int>())
            Do(Step.compute) {
                Assign(result, to: TupleExpr<Int>.literal(1 / divisor, numerator + 1))
            }
            Do(Step.overflow) {
                Assign(result, to: TupleExpr<Int>.literal(numerator + 1, 0))
            }
        }
    }
}

@TLAModel
struct GeneratedConditionalArithmeticFailureModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("GeneratedConditionalArithmeticFailureModel") { scope in
            let attempt = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: SetExpr<Int>.literal(-1, 0))
            let result = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                If(attempt) {
                    Assign(result, to: 1 / divisor)
                } else: {
                    Assign(result, to: 1 / (divisor + 1))
                }
            }
        }
    }
}

@TLAModel
struct GeneratedFallibleConditionModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("GeneratedFallibleConditionModel") { scope in
            let divisor = scope.sharedVar(in: SetExpr<Int>.literal(9_223_372_036_854_775_807, -3, -2, 0))
            let result = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                If(divisor + 1 > 0) {
                    Assign(result, to: 1 / divisor)
                } else: {
                    Assign(result, to: 1 / (divisor + 2))
                }
            }
        }
    }
}

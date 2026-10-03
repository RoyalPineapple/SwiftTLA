import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IntegerRangeMembershipModel: Sendable {
    enum Step: String, CaseIterable {
        case check, large, overflow, candidateFailure, lowerFailure, upperFailure, unionFailure
    }

    static var spec: TLASpec {
        #spec("IntegerRangeMembershipModel") { scope in
            let lower = scope.parameter(as: Int.self, in: -3...3)
            let upper = scope.parameter(as: Int.self, in: -3...3)
            let value = scope.parameter(as: Int.self, in: -4...4)
            let result = scope.sharedVar(initial: false)
            let zero = scope.sharedVar(initial: 0)
            Do(Step.check) {
                Assign(result, to: IntRange(lower, through: upper).contains(value))
            }
            Do(Step.large) {
                Assign(result, to: IntRange(0, through: 1_000_000_000).contains(value))
            }
            Do(Step.overflow) {
                Assign(result, to: IntRange(0, through: 9_223_372_036_854_775_807).contains(1 / zero))
            }
            Do(Step.candidateFailure) {
                Assign(result, to: IntRange(1, through: 0).contains(1 / zero))
            }
            Do(Step.lowerFailure) {
                Assign(result, to: IntRange(1 / zero, through: 9_223_372_036_854_775_807).contains(value))
            }
            Do(Step.upperFailure) {
                Assign(result, to: IntRange(0, through: 1 / zero).contains(value))
            }
            Do(Step.unionFailure) {
                Assign(result, to: IntRange(0, through: 1).union(SetExpr<Int>.literal(1 / zero)).contains(zero))
            }
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CheckedSummationOverflowModel: Sendable {
    enum Step: String, CaseIterable { case sum }

    static var spec: TLASpec {
        #spec("CheckedSummationOverflowModel") { scope in
            Import(FunctionsModule.module)
            let values = scope.sharedVar(initial: [0: 9223372036854775807, 1: 1, 2: 1])
            let total = scope.sharedVar(initial: 0)
            Do(Step.sum) {
                Assign(total, to: Sum(values, over: Set<Int>([0, 1, 2])))
            }
        }
    }
}

@TLAModel
struct CheckedSummationMissingFunctionValueModel: Sendable {
    enum Step: String, CaseIterable { case sum }

    static var spec: TLASpec {
        #spec("CheckedSummationMissingFunctionValueModel") { scope in
            Import(FunctionsModule.module)
            let values = scope.sharedVar(initial: [0: 2])
            let total = scope.sharedVar(initial: 0)
            Do(Step.sum) {
                Assign(total, to: Sum(values, over: Set<Int>([0, 1])))
            }
        }
    }
}

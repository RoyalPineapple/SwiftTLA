import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ThreeArgumentActionModel {
    enum Step: String, CaseIterable { case transfer }

    static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.transfer, over: Set<Int>([1, 2]), Set<Int>([10, 20]), Set<Int>([100, 200])) {
                source, destination, amount in
                When(value == 0)
                Assign(value, to: source + destination + amount)
            }
        }
    }
}

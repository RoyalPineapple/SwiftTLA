import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CheckedAdditionPrefixInitialModel {
    package enum Step: String, CaseIterable { case stay }

    package static var spec: TLASpec {
        #spec {
            let algorithm = Algorithm(label: "CheckedAdditionPrefixInitial", scoped: { scope in
                let first = scope.sharedVar(initial: 1)
                let second = scope.sharedVar(initial: first + 2)
                let last = scope.sharedVar(initial: second + 9223372036854775807)
                Do(Step.stay) { Assign(last, to: last) }
            })
            algorithm
            let validation = Validation(label: "Initial overflow") {}
            validation
        }
    }
}

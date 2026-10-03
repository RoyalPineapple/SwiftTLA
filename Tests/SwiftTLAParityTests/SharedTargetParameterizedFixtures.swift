import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SharedTargetParameterizedModel {
    enum Step: String, CaseIterable { case openDoor }

    static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.openDoor, over: Set<Int>([0, 1])) { trigger in
                Assign(value, to: 1)
            }
        }
    }
}

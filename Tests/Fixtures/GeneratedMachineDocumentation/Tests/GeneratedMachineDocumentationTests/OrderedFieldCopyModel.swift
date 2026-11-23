import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedFieldCopyModel {
    enum Step: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec {
            let copies = Algorithm { scope in
                scope.sharedVar(\State.x, initial: 2)
                scope.sharedVar(\State.y, initial: 3)
                scope.sharedVar(\State.z, initial: 4)
                Do(Step.copy, in: State.self) { state in
                    state.y = state.x
                    state.x = state.z
                    state.z = state.y
                }
            }
            copies
        }
    }
}

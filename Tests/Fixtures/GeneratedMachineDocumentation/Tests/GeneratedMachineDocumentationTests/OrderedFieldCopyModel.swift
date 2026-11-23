import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedFieldCopyModel {
    enum Step: String, CaseIterable { case copy, copyThenReset, resetThenCopy, accumulate, overflow }

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
                Do(Step.copyThenReset, in: State.self) { state in
                    state.x = 7
                    state.y = state.x
                    state.x = 0
                }
                Do(Step.resetThenCopy, in: State.self) { state in
                    state.x = 7
                    state.x = 0
                    state.y = state.x
                }
                Do(Step.accumulate, in: State.self) { state in
                    state.y += 3
                    state.x += state.y
                }
                Do(Step.overflow, in: State.self) { state in
                    state.x = 9_223_372_036_854_775_807
                    state.x += state.y
                }
            }
            copies
        }
    }
}

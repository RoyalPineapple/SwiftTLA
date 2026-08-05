import SwiftTLA

/// A simplified 3-state spec used to verify the checker's BFS logic.
@TLAModel
public struct CheckerProof {
    static var spec: TLASpec {
        TLASpec("CheckerProof") {
            let state = Var<Int>("state", value: 0)
            Variable(state, 0)
            Action("step") { state.becomes(state + 1).when(state < 3) }
            Invariant("valid") { state >= 0 && state <= 3 }
        }
    }
}

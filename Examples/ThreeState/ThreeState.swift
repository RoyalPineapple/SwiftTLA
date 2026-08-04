import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct ThreeState {
    static var spec: TLASpec {
        TLASpec("ThreeState") {
            let state = Var(0)
            Action("to1") { state.becomes(1).when(state == 0) }
            Action("to2") { state.becomes(2).when(state == 1) }
            Action("to0") { state.becomes(0).when(state == 2) }
        }
    }
}

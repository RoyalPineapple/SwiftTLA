import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct PingPong {
    static var spec: TLASpec {
        TLASpec("PingPong") {
            let state = Var(0)
            Action("ping") { state.becomes(1).when(state == 0) }
            Action("pong") { state.becomes(0).when(state == 1) }
        }
    }
}

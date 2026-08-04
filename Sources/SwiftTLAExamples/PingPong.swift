import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct PingPong {
    var state = Var(0)
    func ping() { state.becomes(1).when(state == 0) }
    func pong() { state.becomes(0).when(state == 1) }
}

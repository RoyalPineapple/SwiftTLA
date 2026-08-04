@_spi(Internal) import SwiftTLA
public enum PingPongSpec {
    public static let state = Var<Int>("state")
    public static let spec = TLASpec("PingPong") {
        Variable(state, 0)
        Action("Ping") { state == 0 && state.prime == 1 }
        Action("Pong") { state == 1 && state.prime == 0 }
    }
}

import SwiftTLA
public enum PingPongSpec {
    public static let state = Var<Int>("state")
    public static let spec = TLASpec("PingPong") {
        Variable(state, 0)
        Act("Ping") { state == 0 && state.next == 1 }
        Act("Pong") { state == 1 && state.next == 0 }
    }
}

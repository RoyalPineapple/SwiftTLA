import SwiftTLA

public enum ToggleSpec {
    public static let x = Var<Int>("x")
    public static let spec = TLASpec("Toggle") {
        Variable(x, 0)
        Act("Flip") { x.next == (x + 1) % 2 }
    }
}

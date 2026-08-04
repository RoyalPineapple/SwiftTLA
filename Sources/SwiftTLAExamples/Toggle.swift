@_spi(Internal) import SwiftTLA

public enum ToggleSpec {
    public static let x = Var<Int>("x")
    public static let spec = TLASpec("Toggle") {
        Variable(x, 0)
        Action("Flip") { x.prime == (x + 1) % 2 }
    }
}

@_spi(Internal) import SwiftTLA

public enum BoundedCounterSpec {
    public static let x = Var<Int>("x")
    public static let spec = TLASpec("BoundedCounter") {
        Variable(x, 0)
        Action("Inc") { (x < 3) && (x.next == x + 1) }
        Action("Dec") { (x > -3) && (x.next == x - 1) }
        Invariant("InBound") { (x >= -3) && (x <= 3) }
    }
}

import SwiftTLA

public enum BoundedCounterSpec {
    public static let x = Var<Int>("x")
    public static let spec = TLASpec("BoundedCounter") {
        Variable(x, 0)
        Act("Inc") { (x < 3) && (x.next == x + 1) }
        Act("Dec") { (x > -3) && (x.next == x - 1) }
        Invariant("InBound") { (x >= -3) && (x <= 3) }
    }
}

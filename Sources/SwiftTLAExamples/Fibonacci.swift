@_spi(Internal) import SwiftTLA
public enum FibSpec {
    public static let a = Var<Int>("a"); public static let b = Var<Int>("b"); public static let n = Var<Int>("n")
    public static let spec = TLASpec("Fib") {
        Variable(a, 0); Variable(b, 1); Variable(n, 0)
        Action("Step") { (n < 5) && (a.next == b) && (b.next == a + b) && (n.next == n + 1) }
    }
}

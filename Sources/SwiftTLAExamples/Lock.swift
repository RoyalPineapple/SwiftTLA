@_spi(Internal) import SwiftTLA
public enum LockSpec {
    public static let lock = Var<Int>("lock")
    public static let spec = TLASpec("Lock") {
        Variable(lock, 0)
        Action("Lock") { lock == 0 && lock.prime == 1 }
        Action("Unlock") { lock == 1 && lock.prime == 0 }
        Invariant("Binary") { lock >= 0 && lock <= 1 }
    }
}

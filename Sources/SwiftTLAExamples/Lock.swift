import SwiftTLA
public enum LockSpec {
    public static let lock = Var<Int>("lock")
    public static let spec = TLASpec("Lock") {
        Variable(lock, 0)
        Act("Lock") { lock == 0 && lock.next == 1 }
        Act("Unlock") { lock == 1 && lock.next == 0 }
        Invariant("Binary") { lock >= 0 && lock <= 1 }
    }
}

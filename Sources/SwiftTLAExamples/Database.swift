@_spi(Internal) import SwiftTLA
public enum DatabaseSpec {
    public static let data = Var<Int>("data"); public static let locked = Var<Int>("locked")
    public static let spec = TLASpec("Database") {
        Variable(data, 0); Variable(locked, 0)
        Action("Write") { locked == 0 && data.next == data + 1 && locked.next == 1 }
        Action("Unlock") { locked == 1 && locked.next == 0 && data.next == data }
        Invariant("Consistent") { (locked == 0) || (locked == 1) }
    }
}

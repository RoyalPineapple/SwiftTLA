@_spi(Internal) import SwiftTLA

public enum ThreeStateSpec {
    public static let s = Var<Int>("state")
    public static let spec = TLASpec("ThreeState") {
        Variable(s, 0)
        Action("To1") { s == 0 && s.next == 1 }
        Action("To2") { s == 1 && s.next == 2 }
        Action("To0") { s == 2 && s.next == 0 }
    }
}

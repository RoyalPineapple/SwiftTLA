@_spi(Internal) import SwiftTLA

public enum ThreeStateSpec {
    public static let s = Var<Int>("state")
    public static let spec = TLASpec("ThreeState") {
        Variable(s, 0)
        Action("To1") { s == 0 && s.prime == 1 }
        Action("To2") { s == 1 && s.prime == 2 }
        Action("To0") { s == 2 && s.prime == 0 }
    }
}

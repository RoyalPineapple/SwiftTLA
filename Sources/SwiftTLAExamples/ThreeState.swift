import SwiftTLA

public enum ThreeStateSpec {
    public static let s = Var<Int>("state")
    public static let spec = TLASpec("ThreeState") {
        Variable(s, 0)
        Act("To1") { s == 0 && s.next == 1 }
        Act("To2") { s == 1 && s.next == 2 }
        Act("To0") { s == 2 && s.next == 0 }
    }
}

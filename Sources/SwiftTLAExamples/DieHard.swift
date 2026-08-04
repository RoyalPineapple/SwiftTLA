@_spi(Internal) import SwiftTLA

public enum DieHardSpec {
    public static let jug3 = Var<Int>("jug3")
    public static let jug5 = Var<Int>("jug5")
    public static let spec = TLASpec("DieHard") {
        Variable(jug3, 0); Variable(jug5, 0)
        Action("Fill3") { jug3.prime == 3 }; Action("Fill5") { jug5.prime == 5 }
        Action("Empty3") { jug3.prime == 0 }; Action("Empty5") { jug5.prime == 0 }
        Action("Pour3to5") {
            let pour: ActionExpr = (jug3 + jug5 <= 5) && (jug5.prime == jug3 + jug5) && (jug3.prime == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (jug5.prime == 5) && (jug3.prime == jug3 - (5 - jug5))
            pour || spill
        }
        Action("Pour5to3") {
            let pour: ActionExpr = (jug3 + jug5 <= 3) && (jug3.prime == jug3 + jug5) && (jug5.prime == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (jug3.prime == 3) && (jug5.prime == jug5 - (3 - jug3))
            pour || spill
        }
    }
}

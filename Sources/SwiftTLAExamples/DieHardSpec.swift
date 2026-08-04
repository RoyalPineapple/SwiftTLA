import SwiftTLA

public enum DieHardSpec {
    public static let jug3 = Var<Int>("jug3")
    public static let jug5 = Var<Int>("jug5")
    public static let spec = TLASpec("DieHard") {
        Variable(jug3, 0); Variable(jug5, 0)
        Act("Fill3") { jug3.next == 3 }; Act("Fill5") { jug5.next == 5 }
        Act("Empty3") { jug3.next == 0 }; Act("Empty5") { jug5.next == 0 }
        Act("Pour3to5") {
            let pour: ActionExpr = (jug3 + jug5 <= 5) && (jug5.next == jug3 + jug5) && (jug3.next == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (jug5.next == 5) && (jug3.next == jug3 - (5 - jug5))
            pour || spill
        }
        Act("Pour5to3") {
            let pour: ActionExpr = (jug3 + jug5 <= 3) && (jug3.next == jug3 + jug5) && (jug5.next == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (jug3.next == 3) && (jug5.next == jug5 - (3 - jug3))
            pour || spill
        }
    }
    public static let expectedStates = 16
}

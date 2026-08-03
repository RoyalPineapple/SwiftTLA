import SwiftTLA

enum DieHardExample {
    static let jug3 = Var<Int>("jug3")
    static let jug5 = Var<Int>("jug5")
    static let spec = TLASpec("DieHard") {
        Variable(jug3, 0)
        Variable(jug5, 0)
        Act("Fill3") { next(jug3) == 3 }
        Act("Fill5") { next(jug5) == 5 }
        Act("Empty3") { next(jug3) == 0 }
        Act("Empty5") { next(jug5) == 0 }
        Act("Pour3to5") {
            let pour: ActionExpr = (jug3 + jug5 <= 5) && (next(jug5) == jug3 + jug5) && (next(jug3) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (next(jug5) == 5) && (next(jug3) == jug3 - (5 - jug5))
            pour || spill
        }
        Act("Pour5to3") {
            let pour: ActionExpr = (jug3 + jug5 <= 3) && (next(jug3) == jug3 + jug5) && (next(jug5) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (next(jug3) == 3) && (next(jug5) == jug5 - (3 - jug3))
            pour || spill
        }
    }
    static let expectedStates = 16
}

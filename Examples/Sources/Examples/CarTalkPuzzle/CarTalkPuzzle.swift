import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct CarTalkPuzzle {
    static var spec: TLASpec {
        TLASpec("CarTalkPuzzle") {
            Extends("Naturals")
            let a = Var<Int>("a", value: 1000); let b = Var<Int>("b", value: 1000)
            Variable(a, 1000); Variable(b, 1000)
            Action("Next") { a.becomes(a+1).when(a<9999) || (a==9999) && a.becomes(1000) && b.becomes(b+1).when(b<9999) }
            Invariant("Range") { a >= 1000 && a <= 9999 && b >= 1000 && b <= 9999 }
        }
    }
}

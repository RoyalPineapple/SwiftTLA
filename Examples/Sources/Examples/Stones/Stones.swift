import SwiftTLA

public struct Stones {
    public static var spec: TLASpec {
        TLASpec("Stones") {
            Extends("Naturals")
            let pile = Var<Int>("pile", value: 10)
            Variable(pile, 10)
            Action("Take1") { pile.becomes(pile - 1).when(pile >= 1) }
            Action("Take2") { pile.becomes(pile - 2).when(pile >= 2) }
            Invariant("NonNeg") { pile >= 0 }
        }
    }
}

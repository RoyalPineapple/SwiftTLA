import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct CoffeeCan {
    static var spec: TLASpec {
        TLASpec("CoffeeCan") {
            Extends("Naturals")
            let black = Var("black", value: 5)
            let white = Var("white", value: 5)
            Variable(black, 5)
            Variable(white, 5)
            Definition("MaxBeanCount == 10")
            Definition("BeanCount == black + white")
            Action("PickSameColorBlack") {
                (black + white > 1) && (black >= 2) && black.becomes(black - 1) && white.stays
            }
            Action("PickSameColorWhite") {
                (black + white > 1) && (white >= 2) && black.becomes(black + 1) && white.becomes(white - 2)
            }
            Action("PickDifferentColor") {
                (black + white > 1) && (black >= 1) && (white >= 1) && black.becomes(black - 1) && white.stays
            }
            Action("Termination") {
                (black + white == 1) && black.stays && white.stays
            }
            DeadlockCheck()
        }
    }
}

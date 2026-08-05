import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct CoffeeCan {
    static var spec: TLASpec {
        TLASpec("CoffeeCan") {
            let black = Var("black", 5)
            let white = Var("white", 5)
            Variable(black, 5)
            Variable(white, 5)

            Action("BB") {
                black.becomes(black - 1).when(black >= 2) && white.stays
            }
            Action("WW") {
                white.becomes(white - 2).when(white >= 2) && black.becomes(black + 1)
            }
            Action("BW") {
                white.becomes(white - 1).when(black >= 1 && white >= 1) && black.stays
            }
        }
    }
}

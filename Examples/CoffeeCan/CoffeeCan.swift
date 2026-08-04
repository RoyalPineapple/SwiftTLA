import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct CoffeeCan {
    static var spec: TLASpec {
        TLASpec("CoffeeCan") {
            let black = Var(5)
            let white = Var(5)
            Action("bb") {
                black.becomes(black - 1).when(black >= 2) && white.stays
            }
            Action("ww") {
                white.becomes(white - 2).when(white >= 2) && black.becomes(black + 1)
            }
            Action("bw") {
                white.becomes(white - 1).when(black >= 1 && white >= 1) && black.stays
            }
        }
    }
}

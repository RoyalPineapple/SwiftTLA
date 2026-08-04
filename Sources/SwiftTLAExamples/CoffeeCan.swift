import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct CoffeeCan {
    var black = Var(5)
    var white = Var(5)

    func bb() {
        black.becomes(black - 1).when(black >= 2) && white.stays
    }

    func ww() {
        white.becomes(white - 2).when(white >= 2) && black.becomes(black + 1)
    }

    func bw() {
        white.becomes(white - 1).when(black >= 1 && white >= 1) && black.stays
    }
}

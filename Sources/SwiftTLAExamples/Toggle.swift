import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Toggle {
    var x = Var(0)
    func flip() { x.becomes((x + 1) % 2) }
}

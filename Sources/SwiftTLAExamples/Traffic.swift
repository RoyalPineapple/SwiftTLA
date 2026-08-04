import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Traffic {
    var light = Var(0)
    func next() { light.becomes((light + 1) % 3) }
    var valid: StateExpr { light >= 0 && light <= 2 }
}

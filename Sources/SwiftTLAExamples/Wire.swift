import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Wire {
    var sent = Var(0)
    var received = Var(0)
    var inTransit = Var(0)

    func send() {
        inTransit.becomes(inTransit + 1) &&
        sent.becomes(sent + 1)
    }

    func receive() {
        inTransit.becomes(inTransit - 1).when(inTransit > 0) &&
        received.becomes(received + 1).when(inTransit > 0)
    }

    var noDuplicates: StateExpr { received <= sent }
    var nonNegative: StateExpr { inTransit >= 0 }
}

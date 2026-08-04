import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Ticket {
    var ticket = Var(0)
    var serving = Var(0)

    func enter() {
        ticket.becomes(ticket + 1)
    }

    func serve() {
        serving.becomes(serving + 1).when(ticket > serving)
    }

    var noLostTickets: StateExpr { serving <= ticket }
    var ticketNonNegative: StateExpr { ticket >= 0 && serving >= 0 }
}

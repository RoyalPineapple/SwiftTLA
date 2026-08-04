import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Bakery {
    var ticket0 = Var(0)
    var ticket1 = Var(0)
    var choosing0 = Var(0)
    var choosing1 = Var(0)
    let idle = 0; let choosing = 1; let waiting = 2; let critical = 3

    func start0() {
        choosing0.becomes(choosing).when(choosing0 == idle)
    }
    func start1() {
        choosing1.becomes(choosing).when(choosing1 == idle)
    }

    func getTicket0() {
        ticket0.becomes(ticket1 + 1).when(choosing0 == choosing) &&
        choosing0.becomes(waiting).when(choosing0 == choosing)
    }
    func getTicket1() {
        ticket1.becomes(ticket0 + 1).when(choosing1 == choosing) &&
        choosing1.becomes(waiting).when(choosing1 == choosing)
    }

    func enter0() {
        choosing0.becomes(critical).when(choosing0 == waiting && (ticket1 == 0 || ticket0 < ticket1))
    }
    func enter1() {
        choosing1.becomes(critical).when(choosing1 == waiting && (ticket0 == 0 || ticket1 < ticket0))
    }

    func exit0() { choosing0.becomes(idle).when(choosing0 == critical) }
    func exit1() { choosing1.becomes(idle).when(choosing1 == critical) }

    var mutualExclusion: StateExpr {
        !(choosing0 == critical && choosing1 == critical)
    }
}

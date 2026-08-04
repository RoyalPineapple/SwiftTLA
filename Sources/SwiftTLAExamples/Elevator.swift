import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Elevator {
    var floor = Var(1)
    var dir = Var(1)
    func up() {
        floor.becomes(floor + 1).when(floor < 5)
        dir.becomes(1).when(floor < 5)
    }
    func down() {
        floor.becomes(floor - 1).when(floor > 1)
        dir.becomes(-1).when(floor > 1)
    }
    var validFloor: StateExpr { floor >= 1 && floor <= 5 }
}

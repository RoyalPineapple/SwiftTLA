import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Elevator {
    static var spec: TLASpec {
        TLASpec("Elevator") {
            let floor = Var(1)
            let direction = Var(1)
            Action("up") {
                floor.becomes(floor + 1).when(floor < 5) &&
                direction.becomes(1).when(floor < 5)
            }
            Action("down") {
                floor.becomes(floor - 1).when(floor > 1) &&
                direction.becomes(-1).when(floor > 1)
            }
            Invariant("validFloor") { floor >= 1 && floor <= 5 }
        }
    }
}

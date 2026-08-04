import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Bridge {
    static var spec: TLASpec {
        TLASpec("Bridge") {
            let cars = Var(0)
            let dir = Var(0)
            Action("enter") {
                cars.becomes(cars + 1).when(cars < 3) && dir.stays
            }
            Action("leave") {
                cars.becomes(cars - 1).when(cars > 0) && dir.stays
            }
            Action("switchDir") { dir.becomes((dir + 1) % 2).when(cars == 0) }
        }
    }
}

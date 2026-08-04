import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Bridge {
    var cars = Var(0)
    var dir = Var(0)
    func enter() {
        cars.becomes(cars + 1).when(cars < 3)
        dir.stays
    }
    func leave() {
        cars.becomes(cars - 1).when(cars > 0)
        dir.stays
    }
    func switchDir() { dir.becomes((dir + 1) % 2).when(cars == 0) }
}

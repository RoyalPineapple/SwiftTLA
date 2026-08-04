import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct ThreeState {
    var s = Var(0)
    func to1() { s.becomes(1).when(s == 0) }
    func to2() { s.becomes(2).when(s == 1) }
    func to0() { s.becomes(0).when(s == 2) }
}

import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct DiastolicLoop {
    static var spec: TLASpec {
        TLASpec("DiastolicLoop") {
            let process0 = Var(0)
            let process1 = Var(0)
            let token = Var(0)
            Action("grant0")   { token.becomes(0).when(process0 == 1 && process1 == 0) && process0.becomes(0) }
            Action("grant1")   { token.becomes(1).when(process1 == 1 && process0 == 0) && process1.becomes(0) }
            Action("request0") { process0.becomes(1).when(process0 == 0) }
            Action("request1") { process1.becomes(1).when(process1 == 0) }
        }
    }
}

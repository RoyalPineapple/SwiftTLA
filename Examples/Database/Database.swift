import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Database {
    static var spec: TLASpec {
        TLASpec("Database") {
            let data = Var(0)
            let locked = Var(0)
            Action("write") {
                data.becomes(data + 1).when(locked == 0) &&
                locked.becomes(1).when(locked == 0)
            }
            Action("unlock") {
                locked.becomes(0).when(locked == 1) &&
                data.stays
            }
        }
    }
}

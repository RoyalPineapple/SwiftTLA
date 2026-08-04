import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Lock {
    static var spec: TLASpec {
        TLASpec("Lock") {
            let isLocked = Var(0)
            Action("lock") { isLocked.becomes(1).when(isLocked == 0) }
            Action("unlock") { isLocked.becomes(0).when(isLocked == 1) }
        }
    }
}

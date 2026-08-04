import SwiftTLA
import SwiftTLAGenerator
import SwiftTLAMacros

@TLASpec
public struct Lock {
    var isLocked = Var(0)
    func lock() { isLocked.becomes(1).when(isLocked == 0) }
    func unlock() { isLocked.becomes(0).when(isLocked == 1) }
    var binary: StateExpr { isLocked >= 0 && isLocked <= 1 }
}

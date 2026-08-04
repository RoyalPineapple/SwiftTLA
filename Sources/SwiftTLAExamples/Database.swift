import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Database {
    var data = Var(0)
    var locked = Var(0)
    func write() { 
        data.becomes(data + 1).when(locked == 0)
        locked.becomes(1).when(locked == 0)
    }
    func unlock() {
        locked.becomes(0).when(locked == 1)
        data.stays
    }
}

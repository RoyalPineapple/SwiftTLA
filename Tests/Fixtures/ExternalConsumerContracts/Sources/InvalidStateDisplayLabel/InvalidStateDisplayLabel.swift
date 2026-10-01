import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidStateDisplayLabel {
    static var spec: TLASpec {
        #spec("InvalidStateDisplayLabel") { scope in
            let valid = scope.sharedVar(initial: 0)
            let empty = scope.sharedVar(label: "", initial: 0)
            let safe = Invariant()
            safe { valid == 0 }
        }
    }
}

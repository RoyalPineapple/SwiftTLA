import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidParameterDisplayLabel {
    static var spec: TLASpec {
        #spec("InvalidParameterDisplayLabel") { scope in
            let valid = scope.parameter(as: Int.self, in: 0...2)
            let empty = scope.parameter(as: Int.self, in: 0...2, label: "")
            let safe = Invariant()
            safe { valid >= 0 }
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConjunctiveFrameModel {
    static var spec: TLASpec {
        #spec("ConjunctiveFrameModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("blocked") {
                value.becomes(1)
                value.stays
            }
            SwiftTLA.Action("choose") {
                (value.becomes(1) && value.stays) || value.becomes(0)
            }
        }
    }
}

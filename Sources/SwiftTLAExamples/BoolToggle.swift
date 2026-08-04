import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct BoolToggle {
    static var spec: TLASpec {
        TLASpec("BoolToggle") {
            let isOn = Var(true)
            Action("toggle") { isOn.becomes(!isOn) }
        }
    }
}

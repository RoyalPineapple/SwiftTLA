import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Toggle {
    static var spec: TLASpec {
        TLASpec("Toggle") {
            let x = Var(0)
            Action("flip") { x.becomes((x + 1) % 2) }
        }
    }
}

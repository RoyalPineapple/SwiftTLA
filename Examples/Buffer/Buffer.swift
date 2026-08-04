import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Buffer {
    static var spec: TLASpec {
        TLASpec("Buffer") {
            let buf = Var(0)
            Action("put") { buf.becomes(1).when(buf == 0) }
            Action("get") { buf.becomes(0).when(buf == 1) }
        }
    }
}

import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Buffer {
    var buf = Var(0)
    func put() { buf.becomes(1).when(buf == 0) }
    func get() { buf.becomes(0).when(buf == 1) }
}

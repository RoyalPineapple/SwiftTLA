import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct ProducerConsumer {
    var buffer = Var(0)
    var produced = Var(0)
    var consumed = Var(0)
    let capacity = 3

    func produce() {
        buffer.becomes(buffer + 1).when(buffer < capacity) &&
        produced.becomes(produced + 1).when(buffer < capacity)
    }

    func consume() {
        buffer.becomes(buffer - 1).when(buffer > 0) &&
        consumed.becomes(consumed + 1).when(buffer > 0)
    }

    var bufferBounds: StateExpr { buffer >= 0 && buffer <= capacity }
    var consistent: StateExpr { produced - consumed == buffer }
}

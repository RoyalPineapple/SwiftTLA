import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequenceMappingFixture: Sendable {
    static var spec: TLASpec {
        #spec("SequenceMappingFixture") {
            Assume(SequenceMapping(length: 3) { index in index.expr * 2 } == [2, 4, 6])
            let mapped = Validation {}.checkingDeadlock(false)
            mapped
        }
    }
}

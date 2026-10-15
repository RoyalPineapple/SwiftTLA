import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SignedModuloOutputModel: Sendable {
    enum Step: String, CaseIterable { case modulo }

    static var spec: TLASpec {
        #spec("SignedModuloOutputModel") { scope in
            let dividend = scope.sharedVar(initial: -5)
            let remainder = scope.sharedVar(initial: 0)
            Do(Step.modulo) {
                Assign(remainder, to: dividend % 2)
            }
        }
    }
}

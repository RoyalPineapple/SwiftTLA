import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ViewIdentityCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ViewIdentityCounter") { scope in
            let phase = scope.sharedVar(initial: 0)
            let history = scope.sharedVar(initial: 0)
            Do(Step.advance, when: history < 2) {
                Assign(phase, to: If(phase == 0, then: 1, else: 0))
                Assign(history, to: history + 1)
            }
            let quotient = Validation { }.viewing(phase)
            quotient
            let levelSensitive = Validation { }.viewing(Pair.literal(phase, scope.checkingLevel))
            levelSensitive
        }
    }
}

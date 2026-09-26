import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedCheckingEffects {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedCheckingEffects") { scope in
            let visits = scope.checkingRegister(as: Int.self, initial: 0)
            let observedLevel = scope.checkingRegister(as: Int.self, initial: 0)
            let value = scope.sharedVar(initial: 0)
            Do(Step.advance) {
                When(observedLevel.set(scope.checkingLevel))
                With(IntRange(1, through: 2)) { selected in
                    When(visits.set(visits * 10 + selected))
                    When(selected == 2)
                    Assign(value, to: visits)
                }
            }
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CheckingLevelRandomElementModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("CheckingLevelRandomElement") { scope in
            Extends(.tlc)
            let value = scope.sharedVar(initial: 0)
            Do(Step.advance, when: RandomElement(from: IntRange(1, through: scope.checkingLevel)) == 1) {
                Assign(value, to: value + 1)
            }
        }
    }
}

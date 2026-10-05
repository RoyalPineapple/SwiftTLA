import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RevisitedStateCheckingLevelModel {
    enum Step: String, CaseIterable { case loop }

    static var spec: TLASpec {
        #spec("RevisitedStateCheckingLevel") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.loop) { Assign(value, to: value) }
            Invariant("BeforeThirdState") { scope.checkingLevel < 3 }
        }
    }
}

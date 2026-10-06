import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct TripleHistoryModel {
    enum Step: String, CaseIterable { case record }

    static var spec: TLASpec {
        #spec("TripleHistory") { scope in
            let history = scope.sharedVar(initial: Triple(first: 0, second: 0, third: "init"))
            Do(Step.record) {
                Assign(history, to: Triple.literal(history.first() + 1, history.second(), "recorded"))
            }
        }
    }
}

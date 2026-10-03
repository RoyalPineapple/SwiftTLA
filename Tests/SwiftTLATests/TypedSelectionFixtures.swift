import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IncreasingSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let increasingSelection = Algorithm(label: "IncreasingSelection", scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    Assign(position, to: Select(from: Set<Int>([1, 2, 3])) { candidate in
                        candidate.expr > position
                    })
                }
            })
            increasingSelection
        }
    }
}

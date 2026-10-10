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

@TLAModel
struct ClosedMissingSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let closedMissingSelection = Algorithm(scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                Do(Step.advance) {
                    Assign(position, to: Select(from: Set<Int>([1])) { _ in false })
                }
            })
            closedMissingSelection
        }
    }
}

@TLAModel
struct BooleanSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec("BooleanSelection") { scope in
            let booleanSelection = Algorithm(scoped: { scope in
                let flag = scope.sharedVar(initial: true)
                Do(Step.select) {
                    Assign(flag, to: Select(from: Set<Bool>([true, false])) { _ in true })
                }
            })
            booleanSelection
        }
    }
}

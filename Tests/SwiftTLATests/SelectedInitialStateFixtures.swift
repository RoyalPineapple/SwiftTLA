import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SelectedInitialStateModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SelectedInitialState") {
            Algorithm("SelectedInitialState", scoped: { scope in
                let value = scope.sharedVar(in: 0...100_000)
                let copy: SharedVariable<Int> = scope.sharedVar(initial: value + 1)
                let neighbor = scope.sharedVar(in: IntRange(value, through: value + 1))
                Invariant("NeighborWithinCopy") { neighbor <= copy }
                Do(Step.advance) {
                    Assign(value, to: value + 1)
                }
            })
        }
    }
}

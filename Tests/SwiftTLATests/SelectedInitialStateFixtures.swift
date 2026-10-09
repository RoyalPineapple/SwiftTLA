import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SelectedInitialStateModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SelectedInitialState") {
            let selectedInitialState = Algorithm(label: "SelectedInitialState", scoped: { scope in
                let value = scope.sharedVar(in: 0...100_000)
                let copy: SharedVariable<Int> = scope.sharedVar(initial: value + 1)
                let neighbor = scope.sharedVar(in: IntRange(value, through: value + 1))
                Invariant("NeighborWithinCopy") { neighbor <= copy }
                Do(Step.advance) {
                    Assign(value, to: value + 1)
                }
            })
            selectedInitialState
        }
    }
}

@TLAModel
struct FiniteSetInitialStateModel: Sendable {
    static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(in: Set<Int>([1, 2, 3]))
            let TypeOK = Invariant()
            TypeOK { value >= 1 && value <= 3 }
        }
    }
}

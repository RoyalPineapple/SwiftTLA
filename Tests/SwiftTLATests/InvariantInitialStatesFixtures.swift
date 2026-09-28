import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvariantInitialStatesModel: Sendable {
    enum Step: String, CaseIterable { case idle, active }

    static var spec: TLASpec {
        #spec("InvariantInitialStates") {
            let AllowedInitial = Invariant()
            Algorithm("InvariantInitialStates", scoped: { scope in
                let value = scope.sharedVar(in: 0...1)
                Each(Set<Int>([1, 2]), scoped: { (_: ProcessIdentifier<Int>, scope: ProcessScope) in
                    let choice = scope.localVar(in: Set<Int>([0, 1]))
                    Do(Step.idle) { Assign(choice, to: choice) }
                    Do(Step.active) { Assign(choice, to: choice) }
                })
                AllowedInitial { value == 1 && At(Step.active, Expr<Int>(1)) }
            })
            InitialStates(satisfying: AllowedInitial)
        }
    }
}

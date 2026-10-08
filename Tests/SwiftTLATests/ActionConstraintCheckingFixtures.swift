import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ActionConstrainedCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ActionConstrainedCounter") { scope in
            let counter = Algorithm(label: "ActionConstrainedCounter", scoped: { scope in
                let count = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    When(count < 3)
                    Assign(count, to: count + 1)
                }
                ActionConstraint(on: count) { before, after in after <= 1 }
                Invariant("BelowTwo") { count < 2 }
            })
            counter
        }
    }
}

@TLAModel
struct ActionConstrainedRegisterCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ActionConstrainedRegisterCounter") { scope in
            let inspections = scope.checkingRegister(as: Int.self, initial: 0)
            let counter = Algorithm(label: "ActionConstrainedRegisterCounter", scoped: { scope in
                let count = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    When(count < 3)
                    Assign(count, to: count + 1)
                }
                ActionConstraint(on: count) { before, after in
                    (before < after) && inspections.set(inspections + 1) && after <= 1
                }
            })
            counter
        }
    }
}

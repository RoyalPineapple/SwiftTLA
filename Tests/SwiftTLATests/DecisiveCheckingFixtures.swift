import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DecisiveCounter {
    enum Step: String, CaseIterable { case advance, jump }

    static var spec: TLASpec {
        #spec("DecisiveCounter") { scope in
            let start = scope.parameter(as: Int.self, in: 0...3)
            let unbounded = scope.parameter(as: Bool.self)
            let value = scope.sharedVar(initial: start)
            Do(Step.advance, when: unbounded || value < 2) { Assign(value, to: value + 1) }
            Do(Step.jump, when: value == 0) { Assign(value, to: 2) }
            let belowThree = Invariant()
            belowThree { value < 3 }
            let nonnegative = Temporal()
            nonnegative(.always(value >= 0))
            Validation("Infinite") { Bind(start, to: 0); Bind(unbounded, to: true) }
                .expect(belowThree, .violated)
            Validation("Initial violation") { Bind(start, to: 3); Bind(unbounded, to: true) }
                .expect(belowThree, .violated)
            Validation("Deadlock") { Bind(start, to: 0); Bind(unbounded, to: false) }
                .expectDeadlock(.violated)
            Validation("Exhaustive") { Bind(start, to: 0); Bind(unbounded, to: false) }
                .checkingDeadlock(false)
        }
    }
}

@TLAModel
struct DecisiveConstraintCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("DecisiveConstraintCounter") { scope in
            let value = scope.sharedVar(initial: 0)
            Algorithm("Counter") {
                Do(Step.advance) {
                    Assign(value, to: value + 1)
                    Goto(Step.advance)
                }
                StateConstraint(value < 2)
            }
            let belowTwo = Invariant()
            belowTwo { value < 2 }
            Validation("Boundary") {}.expect(belowTwo, .violated)
        }
    }
}

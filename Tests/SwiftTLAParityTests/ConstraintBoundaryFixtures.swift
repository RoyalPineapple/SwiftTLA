import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConstraintBoundaryCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConstraintBoundaryCounter") { scope in
            let safetyLimit = scope.parameter(as: Int.self, in: 2...3)
            let count = scope.sharedVar("count", initial: 0)
            Algorithm("Counter") {
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                    Goto(Step.advance)
                }
                StateConstraint(count < 2)
            }
            Invariant("Bounded") { count < safetyLimit }
        }
    }
}

@TLAModel
struct ConstraintInitialCounter {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("ConstraintInitialCounter") { scope in
            let count = scope.sharedVar("count", in: 0...2)
            Algorithm("Counter") {
                Do(Step.stay) {
                    Skip()
                    Goto(Step.stay)
                }
                StateConstraint(count < 2)
            }
            Invariant("Bounded") { count < 2 }
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConstraintReachabilityCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConstraintReachabilityCounter") { scope in
            let excluded = Reachable()
            let counter = Algorithm(label: "Counter", scoped: { scope in
                let count = scope.sharedVar(initial: 0)
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                    Goto(Step.advance)
                }
                StateConstraint(count < 2)
                excluded { count == 2 }
            })
            counter
        }
    }
}

@TLAModel
struct ConstraintBoundaryCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConstraintBoundaryCounter") { scope in
            let safetyLimit = scope.parameter(as: Int.self, in: 2...3)
            let count = scope.sharedVar(_name: "count", initial: 0)
            let counter = Algorithm(label: "Counter") {
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                    Goto(Step.advance)
                }
                StateConstraint(count < 2)
            }
            counter
            Invariant("Bounded") { count < safetyLimit }
        }
    }
}

@TLAModel
struct ConstraintInitialCounter {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("ConstraintInitialCounter") { scope in
            let count = scope.sharedVar(_name: "count", in: 0...2)
            let counter = Algorithm(label: "Counter") {
                Do(Step.stay) {
                    Skip()
                    Goto(Step.stay)
                }
                StateConstraint(count < 2)
            }
            counter
            Invariant("Bounded") { count < 2 }
        }
    }
}

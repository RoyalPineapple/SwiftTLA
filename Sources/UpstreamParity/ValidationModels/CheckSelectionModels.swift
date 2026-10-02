import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SelectedChecksModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SelectedChecks") { scope in
            let value = scope.sharedVar(initial: 0)
            let Advance = Algorithm {
                Do(Step.advance, when: value == 0) {
                    Assign(value, to: 1)
                    Goto(Step.advance)
                }
            }
            Advance
            let safe = Invariant("Safe") { value >= 0 }
            let initiallyZero = Invariant("InitiallyZero") { value == 0 }
            let reached = Reachable("Reached") { value == 1 }
            let staysZero = Always("StaysZero", value == 0)
            safe
            initiallyZero
            reached
            staysZero
            let All = Validation {}
                .expect(initiallyZero, .violated).expect(staysZero, .violated).expectDeadlock(.violated)
            All
            let Selected = Validation {}.checking(only: [safe, reached]).checkingDeadlock(false)
            Selected
            let graphOnly = Validation(label: "Graph only") {}.checking(only: []).checkingDeadlock(false)
            graphOnly
        }
    }
}

@TLAModel
struct UnselectedPredicateModel {
    enum Step: String, CaseIterable { case wait }

    static var spec: TLASpec {
        #spec("UnselectedPredicate") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let Blocked = Algorithm {
                Do(Step.wait, when: divisor < 0) { Goto(Step.wait) }
            }
            Blocked
            let invariant = Invariant("UndefinedInvariant") { 1 / divisor == 0 }
            let goal = Reachable("UndefinedGoal") { 1 / divisor == 0 }
            let temporal = Always("UndefinedTemporal", 1 / divisor == 0)
            invariant
            goal
            temporal
            let graphOnly = Validation(label: "Graph only") {}.checking(only: []).checkingDeadlock(false)
            graphOnly
        }
    }
}

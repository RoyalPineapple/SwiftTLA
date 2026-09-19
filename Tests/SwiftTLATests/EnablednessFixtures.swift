import SwiftTLA
import SwiftTLAMacros

// Formal-boundary fixture: an invalid action exposes premature enabledness evaluation.
@TLAModel
struct GuardedEnabledness {
    enum Step: String, CaseIterable { case divide, stay, guardedStay, blocked }

    static var spec: TLASpec {
        #spec("GuardedEnabledness") { scope in
            let count = scope.sharedVar(initial: 0)
            let divide = Do(Step.divide) { Assign(count, to: 1 / count) }
            let stay = Do(Step.stay) { Skip() }
            let guardedStay = Do(Step.guardedStay) {
                When(count == 0 || divide.enabled)
            }
            let blocked = Do(Step.blocked) {
                When(count > 0 && divide.enabled)
            }
            divide
            stay
            guardedStay
            blocked
            Constraint(count == 0 || divide.enabled)
            let guardedInvariant = Invariant()
            let demandedInvariant = Invariant()
            let guardedReachable = Reachable()
            let demandedReachable = Reachable()
            guardedInvariant { count == 0 || divide.enabled }
            demandedInvariant { divide.enabled }
            guardedReachable { count == 0 || divide.enabled }
            demandedReachable { divide.enabled }
            let stutter = Temporal()
            let guarded = Temporal()
            let alternative = Temporal()
            let demanded = Temporal()
            let transitive = Temporal()
            stutter(.alwaysStep(on: count) { before, after in divide.enabled })
            guarded(.always(count == 0 || divide.enabled))
            alternative(.always(stay.enabled || divide.enabled))
            demanded(.always(divide.enabled))
            transitive(.always(guardedStay.enabled))
        }
    }
}

@TLAModel
struct BoundStepEnabledness {
    enum Step: String, CaseIterable { case advance, finish }

    static var spec: TLASpec {
        #spec("BoundStepEnabledness") { scope in
            let choices = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1, 2])]))
            let count = scope.sharedVar(initial: 0)
            let advance = Do(Step.advance, over: choices) { amount in
                When(count < 2)
                Assign(count, to: count + amount)
            }
            let finish = Do(Step.finish, when: count >= 2) { Skip() }
            advance
            finish
            WeakFairness(advance)
            StrongFairness(finish)
            Invariant("Enabled") {
                advance.enabled == (!choices.isEmpty && count < 2)
                    && finish.enabled == (count >= 2)
            }
            let Finished = Temporal()
            Finished(.eventually(finish.enabled))
            Validation("Choices") { Bind(choices, to: Set<Int>([1, 2])) }
        }
    }
}

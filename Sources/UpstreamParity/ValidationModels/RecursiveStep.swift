import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RecursiveStep {
    package enum Step: String, CaseIterable { case compute }

    package static var spec: TLASpec {
        #spec { scope in
            let total = scope.sharedVar(initial: 0)
            let computed = Reachable()
            Do(Step.compute, when: total == 0) {
                Assign(total, to: LetRec("SumTo", over: IntRange(0, through: 4), taking: Int.self,
                    { (sum: LocalRecursion<Int, Int>, number: WithValue<Int>) in
                        If(number == 0, then: 0, else: number.expr + sum(number.expr - 1))
                    }, in: { sum in sum(4) }))
            }
            computed { total == 10 }
            Validation("Complete") {}.expectDeadlock(.violated)
        }
    }
}

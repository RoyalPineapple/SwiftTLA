import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ReachabilityCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ReachabilityCounter") { scope in
            let target = scope.parameter(as: Int.self, in: 0...3)
            let exploredThrough = scope.parameter(as: Int.self, in: 1...2)
            let count = scope.sharedVar(initial: 0)
            Algorithm("Counter") {
                Do(Step.advance, when: count < 2) {
                    Assign(count, to: count + 1)
                    Goto(Step.advance)
                }
                StateConstraint(count <= exploredThrough)
            }
            Invariant("Bounded") { count <= 2 }
            Reachable("Target") { count == target }
        }
    }
}

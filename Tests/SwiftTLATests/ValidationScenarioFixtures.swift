import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ScenarioExpectations {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ScenarioExpectations") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...2)
            let value = scope.sharedVar("value", initial: 0)
            Algorithm("Counter") {
                Do(Step.advance, when: value < limit) {
                    Assign(value, to: value + 1)
                    Goto(Step.advance)
                }
            }
            let bounded = Invariant("Bounded") { value <= limit }
            let beyondLimit = Reachable("BeyondLimit") { value > limit }
            bounded
            beyondLimit
            Validation("Expected unreachable goal") {
                Bind(limit, to: 2)
            }.expect(beyondLimit, .violated).expectDeadlock(.violated)
        }
    }
}

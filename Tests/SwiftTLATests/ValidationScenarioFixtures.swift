import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ScenarioExpectations {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ScenarioExpectations") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...2)
            let value = scope.sharedVar(_name: "value", initial: 0)
            let counter = Algorithm(label: "Counter") {
                Do(Step.advance, when: value < limit) {
                    Assign(value, to: value + 1)
                    Goto(Step.advance)
                }
            }
            counter
            let bounded = Invariant("Bounded") { value <= limit }
            let beyondLimit = Reachable("BeyondLimit") { value > limit }
            bounded
            beyondLimit
            let expectedUnreachableGoal = Validation(label: "Expected unreachable goal") {
                Bind(limit, to: 2)
            }.expect(beyondLimit, .violated).expectDeadlock(.violated)
            expectedUnreachableGoal
        }
    }
}

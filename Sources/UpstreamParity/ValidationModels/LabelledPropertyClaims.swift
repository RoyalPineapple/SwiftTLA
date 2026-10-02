import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct LabelledPropertyClaims {
    package enum Step: String, CaseIterable { case stay }

    package static var spec: TLASpec {
        #spec {
            let safe = SwiftTLA.Invariant(label: "Safety / progress")
            let reachable = Reachable(label: "Safety / progress")
            let always = Always(label: "Safety / progress")
            let eventually = Eventually(label: "Safety / progress")
            let recurring = AlwaysEventually(label: "Safety / progress")
            let stable = EventuallyAlways(label: "Safety / progress")
            let response = LeadsTo(label: "Safety / progress")
            let Loop = Algorithm(scoped: { scope in
                let value = scope.sharedVar(initial: 0)
                Do(Step.stay) {
                    Assign(value, to: value)
                    Goto(Step.stay)
                }
                safe { value == 1 }
                reachable { value == 0 }
                always(value == 0)
                eventually(value == 1)
                recurring(value == 0)
                stable(value == 0)
                response(value == 0, value == 0)
            })
            Loop
            let All = Validation(label: "Shared scenario") {}
                .expect(safe, .violated)
                .expect(eventually, .violated)
            All
            let Selected = Validation(label: "Shared scenario") {}.checking(only: [reachable, always])
            Selected
        }
    }
}

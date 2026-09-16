import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct QualifiedPropertyClaims {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("QualifiedPropertyClaims") {
            let safe = SwiftTLA.Invariant()
            let reachable = SwiftTLA.Reachable()
            let always = SwiftTLA.Always()
            let eventually = SwiftTLA.Eventually()
            let recurring = SwiftTLA.AlwaysEventually()
            let stable = SwiftTLA.EventuallyAlways()
            let response = SwiftTLA.LeadsTo()
            Algorithm("Loop", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Do(Step.stay) {
                    Assign(value, to: value)
                    Goto(Step.stay)
                }
                safe { value == 0 }
                reachable { value == 0 }
                always(value == 0)
                eventually(value == 0)
                recurring(value == 0)
                stable(value == 0)
                response(value == 0, value == 0)
            })
            Validation("All") {}
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ActionReferencesModel {
    static var spec: TLASpec {
        #spec("ActionReferences") { scope in
            let count = scope.sharedVar(initial: 0)
            let amount = ActionParameter("amount", values: [1, 2])
            let advance = SwiftTLA.Action("Advance", parameters: [amount]) {
                count.becomes(amount).when(count == 0)
            }
            advance
            SwiftTLA.Action("Stay") { count.becomes(count).when(count > 0) }
            Invariant("CanAdvance") {
                StateExpr.enabled(advance) || (count > 0).stateExpr
            }
            Invariant("InRange") { count >= 0 && count <= 2 }
            Eventually("EventuallyAdvanced", count > 0)
            WeakFairness(advance)
        }
    }
}

import SwiftTLA
import SwiftTLAMacros

// Formal-boundary fixture: an invalid action exposes premature enabledness evaluation.
@TLAModel
struct GuardedEnabledness {
    static var spec: TLASpec {
        #spec("GuardedEnabledness") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let divide = SwiftTLA.Action("divide") { count.becomes(1 / count) }
            let stay = SwiftTLA.Action("stay") { count.becomes(count) }
            let guardedStay = SwiftTLA.Action("guardedStay") {
                count.becomes(count).when(count == 0 || Expr<Bool>(StateExpr.enabled(divide)))
            }
            let blocked = SwiftTLA.Action("blocked") {
                count.becomes(count).when(count > 0 && Expr<Bool>(StateExpr.enabled(divide)))
            }
            divide
            stay
            guardedStay
            blocked
            Constraint(count == 0 || Expr<Bool>(StateExpr.enabled(divide)))
            let guardedInvariant = Invariant()
            let demandedInvariant = Invariant()
            let guardedReachable = Reachable()
            let demandedReachable = Reachable()
            guardedInvariant { count == 0 || Expr<Bool>(StateExpr.enabled(divide)) }
            demandedInvariant { Expr<Bool>(StateExpr.enabled(divide)) }
            guardedReachable { count == 0 || Expr<Bool>(StateExpr.enabled(divide)) }
            demandedReachable { Expr<Bool>(StateExpr.enabled(divide)) }
            let stutter = Temporal()
            let guarded = Temporal()
            let alternative = Temporal()
            let demanded = Temporal()
            let transitive = Temporal()
            stutter(.alwaysStep(on: count) { before, after in Expr<Bool>(StateExpr.enabled(divide)) })
            guarded(.always(count == 0 || Expr<Bool>(StateExpr.enabled(divide))))
            alternative(.always(Expr<Bool>(StateExpr.enabled(stay)) || Expr<Bool>(StateExpr.enabled(divide))))
            demanded(.always(Expr<Bool>(StateExpr.enabled(divide))))
            transitive(.always(Expr<Bool>(StateExpr.enabled(guardedStay))))
        }
    }
}

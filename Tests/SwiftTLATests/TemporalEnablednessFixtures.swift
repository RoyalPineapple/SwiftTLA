import SwiftTLA
import SwiftTLAMacros

// Formal-boundary fixture: an invalid action exposes premature enabledness evaluation.
@TLAModel
struct GuardedTemporalEnabledness {
    static var spec: TLASpec {
        #spec("GuardedTemporalEnabledness") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let divide = SwiftTLA.Action("divide") { count.becomes(1 / count) }
            let stay = SwiftTLA.Action("stay") { count.becomes(count) }
            divide
            stay
            let stutter = Temporal()
            let guarded = Temporal()
            let alternative = Temporal()
            let demanded = Temporal()
            stutter(.alwaysStep(on: count) { before, after in Expr<Bool>(StateExpr.enabled(divide)) })
            guarded(.always(count == 0 || Expr<Bool>(StateExpr.enabled(divide))))
            alternative(.always(Expr<Bool>(StateExpr.enabled(stay)) || Expr<Bool>(StateExpr.enabled(divide))))
            demanded(.always(Expr<Bool>(StateExpr.enabled(divide))))
        }
    }
}

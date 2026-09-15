import SwiftTLA
import SwiftTLAMacros

// Independent formal actions exercise generated failures without advancing process control.
@TLAModel
struct FunctionSpaceMembershipModel {
    enum Key: String, CaseIterable, FiniteTLAValueDomain { case first, second, third }

    static var spec: TLASpec {
        TLASpec("FunctionSpaceMembershipModel") {
            let result = Var<Bool>("result")
            let zero = Var<Int>("zero")
            Variable(result, false)
            Variable(zero, 0)
            SwiftTLA.Action("accepted") {
                result.becomes(Functions(from: Key.all, to: SetExpr<Int>.literal(0, 1))
                    .contains(Function<Key, Int>.mapping { _ in 0 }))
            }
            SwiftTLA.Action("candidateFailure") {
                result.becomes(Functions(from: Key.all, to: SetExpr<Int>())
                    .contains(Function<Key, Int>.mapping { _ in 1 / zero.expr }))
            }
        }
    }
}

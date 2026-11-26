// A voucher can be issued, transferred, redeemed, or canceled.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/byihive/VoucherLifeCycle.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct VoucherLifeCycleModel: Sendable {
    package enum Voucher: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, v3
        package static var defaultValue: Self { .v1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Status: String, CaseIterable { case phantom, valid, redeemed, cancelled }
    package enum Phase: String, CaseIterable { case initial = "init", working, done }
    private enum Step: String, CaseIterable {
        case issue = "Issue", transfer = "Transfer", redeem = "Redeem", cancel = "Cancel"
    }

    package static var spec: TLASpec {
        #spec("VoucherLifeCycle") { scope in
            let V = scope.parameter(as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let vState = scope.sharedVar(initial: Dictionary<Voucher, Status>.mapping(over: V) { _ in Status.phantom })
            let vlcState = scope.sharedVar(initial: Dictionary<Voucher, Phase>.mapping(over: V) { _ in Phase.initial })

            Do(Step.issue, over: V) { v in
                When(vState[v] == Status.phantom && vlcState[v] == Phase.initial)
                vState[v].set(Status.valid)
                vlcState[v].set(Phase.working)
            }
            Do(Step.transfer, over: V) { v in
                When(vState[v] == Status.valid)
                Skip()
            }
            Do(Step.redeem, over: V) { v in
                When(vState[v] == Status.valid && vlcState[v] == Phase.working)
                vState[v].set(Status.redeemed)
                vlcState[v].set(Phase.done)
            }
            Do(Step.cancel, over: V) { v in
                When(vState[v] == Status.valid && vlcState[v] == Phase.working)
                vState[v].set(Status.cancelled)
                vlcState[v].set(Phase.done)
            }

            Invariant("VTypeOK") {
                Functions(from: V, to: SetExpr<Status>.literal(.phantom, .valid, .redeemed, .cancelled)).contains(vState)
                Functions(from: V, to: SetExpr<Phase>.literal(.initial, .working, .done)).contains(vlcState)
            }
            Invariant("VConsistent") {
                V.allSatisfy { v in
                    (vlcState[v] == Phase.done && (vState[v] == Status.redeemed || vState[v] == Status.cancelled))
                        || (vlcState[v] == Phase.initial && vState[v] == Status.phantom)
                        || (vlcState[v] == Phase.working && vState[v] == Status.valid)
                }
            }
            Validation("published") {
                Bind(V, to: Set<Voucher>([.v1, .v2, .v3]))
            }.checkingDeadlock(false)
        }
    }
}

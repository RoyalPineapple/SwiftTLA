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
            let vouchers = scope.parameter(tlaName: "V", as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let voucherStatus = scope.sharedVar(tlaName: "vState", initial: Dictionary<Voucher, Status>.mapping(over: vouchers) { _ in Status.phantom })
            let lifecyclePhase = scope.sharedVar(tlaName: "vlcState", initial: Dictionary<Voucher, Phase>.mapping(over: vouchers) { _ in Phase.initial })

            Do(Step.issue, over: vouchers) { v in
                When(voucherStatus[v] == Status.phantom && lifecyclePhase[v] == Phase.initial)
                voucherStatus[v].set(Status.valid)
                lifecyclePhase[v].set(Phase.working)
            }
            Do(Step.transfer, over: vouchers) { v in
                When(voucherStatus[v] == Status.valid)
                Skip()
            }
            Do(Step.redeem, over: vouchers) { v in
                When(voucherStatus[v] == Status.valid && lifecyclePhase[v] == Phase.working)
                voucherStatus[v].set(Status.redeemed)
                lifecyclePhase[v].set(Phase.done)
            }
            Do(Step.cancel, over: vouchers) { v in
                When(voucherStatus[v] == Status.valid && lifecyclePhase[v] == Phase.working)
                voucherStatus[v].set(Status.cancelled)
                lifecyclePhase[v].set(Phase.done)
            }

            Invariant("VTypeOK") {
                Functions(from: vouchers, to: SetExpr<Status>.literal(.phantom, .valid, .redeemed, .cancelled)).contains(voucherStatus)
                Functions(from: vouchers, to: SetExpr<Phase>.literal(.initial, .working, .done)).contains(lifecyclePhase)
            }
            Invariant("VConsistent") {
                vouchers.allSatisfy { v in
                    (lifecyclePhase[v] == Phase.done && (voucherStatus[v] == Status.redeemed || voucherStatus[v] == Status.cancelled))
                        || (lifecyclePhase[v] == Phase.initial && voucherStatus[v] == Status.phantom)
                        || (lifecyclePhase[v] == Phase.working && voucherStatus[v] == Status.valid)
                }
            }
            Validation("published") {
                Bind(vouchers, to: Set<Voucher>([.v1, .v2, .v3]))
            }.checkingDeadlock(false)
        }
    }
}

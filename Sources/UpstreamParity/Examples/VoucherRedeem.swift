// A holder and a collector exchange messages to redeem a voucher.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/byihive/VoucherRedeem.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct VoucherRedeemModel: Sendable {
    package enum Voucher: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, v3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .v1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Participant: String, CaseIterable, FiniteTLAValueDomain {
        case holder1, holder2, holder3, collector1, collector2, collector3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .holder1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct HolderPrepared: Hashable, Sendable {
        package let type: String
        package let vh: Participant
    }
    package struct CollectorPrepared: Hashable, Sendable {
        package let type: String
        package let vc: Participant
    }
    package struct Broadcast: Hashable, Sendable { package let type: String }
    package typealias OtherMessage = OneOf<CollectorPrepared, Broadcast>
    package typealias Message = OneOf<HolderPrepared, OtherMessage>
    private enum Step: String, CaseIterable {
        case providerRecordsPreparedPair = "VTPRcvPrepared"
        case providerRedeem = "VTPRedeem"
        case providerAbort = "VTPAbort"
        case holderPrepare = "HPrepare"
        case holderChooseToAbort = "HChooseToAbort"
        case holderReceivesRedeem = "HRcvRedeemMsg"
        case holderReceivesAbort = "HRcvAbortMsg"
        case collectorPrepare = "CPrepare"
        case collectorChooseToAbort = "CChooseToAbort"
        case collectorReceivesRedeem = "CRcvRedeemMsg"
        case collectorReceivesAbort = "CRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherRedeem") { scope in
            let vouchers = scope.parameter(tlaName: "V", as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let holders = scope.parameter(tlaName: "H", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let collectors = scope.parameter(tlaName: "C", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = holders.union(collectors)
            let voucherStatus = scope.sharedVar(tlaName: "vState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "valid" })
            let lifecyclePhase = scope.sharedVar(tlaName: "vlcState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "working" })
            let holderState = scope.sharedVar(tlaName: "hState", initial: Dictionary<Participant, String>.mapping(over: holders) { _ in "holding" })
            let collectorState = scope.sharedVar(tlaName: "cState", initial: Dictionary<Participant, String>.mapping(over: collectors) { _ in "waiting" })
            let transactionProviderState = scope.sharedVar(tlaName: "vtpState", initial: "init")
            let preparedParticipants = scope.sharedVar(tlaName: "vtpRPrepared", initial: Set<Participant>())
            let messages = scope.sharedVar(tlaName: "msgs", initial: Set<Message>())
            let redeemMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Redeem")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            let allVouchersAreValid = Functions(from: vouchers, to: SetExpr<String>.literal("valid")).contains(voucherStatus)
            let allLifecyclesAreWorking = Functions(from: vouchers, to: SetExpr<String>.literal("working")).contains(lifecyclePhase)

            Do(Step.providerRecordsPreparedPair, over: participants, participants) { h, c in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(transactionProviderState == "init")
                When(messages.contains(Message.first(HolderPrepared.expression(type: "Prepared", vh: h))))
                When(messages.contains(Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: c)))))
                preparedParticipants.insert(h)
                preparedParticipants.insert(c)
            }

            Do(Step.providerRedeem, over: vouchers) { v in
                When(voucherStatus[v] == "valid")
                When(lifecyclePhase[v] == "working")
                When(transactionProviderState == "init")
                When(preparedParticipants == participants)
                transactionProviderState.set("done")
                voucherStatus[v].set("redeemed")
                lifecyclePhase[v].set("done")
                messages.insert(redeemMessage)
            }

            Do(Step.providerAbort, over: vouchers) { v in
                When(voucherStatus[v] == "valid")
                When(lifecyclePhase[v] == "working")
                When(transactionProviderState == "init")
                transactionProviderState.set("done")
                messages.insert(abortMessage)
            }

            Do(Step.holderPrepare, over: holders) { h in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(holderState[h] == "holding")
                holderState[h].set("prepared")
                messages.insert(Message.first(HolderPrepared.expression(type: "Prepared", vh: h)))
            }

            Do(Step.holderChooseToAbort, over: holders) { h in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(holderState[h] == "holding")
                holderState[h].set("aborted")
            }

            Do(Step.holderReceivesRedeem, over: holders) { h in
                When(Functions(from: vouchers, to: SetExpr<String>.literal("valid", "redeemed")).contains(voucherStatus))
                When(Functions(from: vouchers, to: SetExpr<String>.literal("working", "done")).contains(lifecyclePhase))
                When(holderState[h] == "holding")
                When(messages.contains(redeemMessage))
                holderState[h].set("redeemed")
            }

            Do(Step.holderReceivesAbort, over: holders) { h in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(holderState[h] == "holding")
                When(messages.contains(abortMessage))
                holderState[h].set("aborted")
            }

            Do(Step.collectorPrepare, over: collectors) { c in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(collectorState[c] == "waiting")
                collectorState[c].set("prepared")
                messages.insert(Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: c))))
            }

            Do(Step.collectorChooseToAbort, over: collectors) { c in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(collectorState[c] == "waiting")
                collectorState[c].set("aborted")
            }

            Do(Step.collectorReceivesRedeem, over: collectors) { c in
                When(Functions(from: vouchers, to: SetExpr<String>.literal("valid", "redeemed")).contains(voucherStatus))
                When(Functions(from: vouchers, to: SetExpr<String>.literal("working", "done")).contains(lifecyclePhase))
                When(collectorState[c] == "waiting")
                When(messages.contains(redeemMessage))
                collectorState[c].set("redeemed")
            }

            Do(Step.collectorReceivesAbort, over: collectors) { c in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(collectorState[c] == "waiting")
                When(messages.contains(abortMessage))
                collectorState[c].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: vouchers, to: SetExpr<String>.literal("valid", "redeemed")).contains(voucherStatus)
                Functions(from: vouchers, to: SetExpr<String>.literal("working", "done")).contains(lifecyclePhase)
                Functions(from: holders, to: SetExpr<String>.literal("holding", "prepared", "redeemed", "aborted")).contains(holderState)
                Functions(from: collectors, to: SetExpr<String>.literal("waiting", "prepared", "redeemed", "aborted")).contains(collectorState)
                SetExpr<String>.literal("init", "done").contains(transactionProviderState)
                preparedParticipants.isSubset(of: participants)
                messages.allSatisfy { message in
                    message == redeemMessage || message == abortMessage
                        || holders.contains { holder in message == Message.first(HolderPrepared.expression(type: "Prepared", vh: holder)) }
                        || collectors.contains { collector in message == Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: collector))) }
                }
            }
            Invariant("VTPConsistent") {
                holders.allSatisfy { h in
                    collectors.allSatisfy { c in
                        !(holderState[h] == "redeemed" && collectorState[c] == "aborted")
                            && !(holderState[h] == "aborted" && collectorState[c] == "redeemed")
                    }
                }
            }
            Validation("published") {
                Bind(vouchers, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(holders, to: Set<Participant>([.holder1, .holder2, .holder3]))
                Bind(collectors, to: Set<Participant>([.collector1, .collector2, .collector3]))
            }.checkingDeadlock(false)
        }
    }
}

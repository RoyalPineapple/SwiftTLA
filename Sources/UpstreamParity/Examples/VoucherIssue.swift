// A voucher moves from its issuer to a holder through a prepare-and-complete exchange.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/byihive/VoucherIssue.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct VoucherIssueModel: Sendable {
    package enum Voucher: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, v3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .v1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Participant: String, CaseIterable, FiniteTLAValueDomain {
        case holder1, holder2, holder3, issuer1, issuer2, issuer3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .holder1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct HolderPrepared: Hashable, Sendable {
        package let type: String
        package let vh: Participant
    }
    package struct IssuerPrepared: Hashable, Sendable {
        package let type: String
        package let vi: Participant
    }
    package struct Broadcast: Hashable, Sendable { package let type: String }
    package typealias OtherMessage = OneOf<IssuerPrepared, Broadcast>
    package typealias Message = OneOf<HolderPrepared, OtherMessage>
    private enum Step: String, CaseIterable {
        case providerRecordsPreparedPair = "VTPRcvPrepared"
        case providerIssue = "VTPIssue"
        case providerAbort = "VTPAbort"
        case holderPrepare = "HPrepare"
        case holderChooseToAbort = "HChooseToAbort"
        case holderReceivesIssue = "HRcvIssueMsg"
        case holderReceivesAbort = "HRcvAbortMsg"
        case issuerPrepare = "IPrepare"
        case issuerChooseToAbort = "IChooseToAbort"
        case issuerReceivesIssue = "IRcvIssueMsg"
        case issuerReceivesAbort = "IRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherIssue") { scope in
            let vouchers = scope.parameter(tlaName: "V", as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let holders = scope.parameter(tlaName: "H", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let issuers = scope.parameter(tlaName: "I", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = holders.union(issuers)
            let voucherStatus = scope.sharedVar(tlaName: "vState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "phantom" })
            let lifecyclePhase = scope.sharedVar(tlaName: "vlcState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "init" })
            let holderState = scope.sharedVar(tlaName: "hState", initial: Dictionary<Participant, String>.mapping(over: holders) { _ in "waiting" })
            let issuerState = scope.sharedVar(tlaName: "iState", initial: Dictionary<Participant, String>.mapping(over: issuers) { _ in "waiting" })
            let transactionProviderState = scope.sharedVar(tlaName: "vtpState", initial: "init")
            let preparedParticipants = scope.sharedVar(tlaName: "vtpIPrepared", initial: Set<Participant>())
            let messages = scope.sharedVar(tlaName: "msgs", initial: Set<Message>())
            let issueMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Issue")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            let allVouchersAreUnissued = Functions(from: vouchers, to: SetExpr<String>.literal("phantom")).contains(voucherStatus)
            let allLifecyclesAreInitial = Functions(from: vouchers, to: SetExpr<String>.literal("init")).contains(lifecyclePhase)

            Do(Step.providerRecordsPreparedPair, over: participants, participants) { h, i in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(transactionProviderState == "init")
                When(messages.contains(Message.first(HolderPrepared.expression(type: "Prepared", vh: h))))
                When(messages.contains(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i)))))
                preparedParticipants.insert(h)
                preparedParticipants.insert(i)
            }

            Do(Step.providerIssue, over: vouchers) { v in
                When(voucherStatus[v] == "phantom")
                When(lifecyclePhase[v] == "init")
                When(transactionProviderState == "init")
                When(preparedParticipants == participants)
                transactionProviderState.set("done")
                voucherStatus[v].set("valid")
                lifecyclePhase[v].set("working")
                messages.insert(issueMessage)
            }

            Do(Step.providerAbort, over: vouchers) { v in
                When(voucherStatus[v] == "phantom")
                When(lifecyclePhase[v] == "init")
                When(transactionProviderState == "init")
                transactionProviderState.set("done")
                messages.insert(abortMessage)
            }

            Do(Step.holderPrepare, over: holders) { h in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(holderState[h] == "waiting")
                holderState[h].set("prepared")
                messages.insert(Message.first(HolderPrepared.expression(type: "Prepared", vh: h)))
            }

            Do(Step.holderChooseToAbort, over: holders) { h in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(holderState[h] == "waiting")
                holderState[h].set("aborted")
            }

            Do(Step.holderReceivesIssue, over: holders) { h in
                When(Functions(from: vouchers, to: SetExpr<String>.literal("phantom", "valid")).contains(voucherStatus))
                When(Functions(from: vouchers, to: SetExpr<String>.literal("init", "working")).contains(lifecyclePhase))
                When(holderState[h] == "waiting")
                When(messages.contains(issueMessage))
                holderState[h].set("holding")
            }

            Do(Step.holderReceivesAbort, over: holders) { h in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(holderState[h] == "waiting")
                When(messages.contains(abortMessage))
                holderState[h].set("aborted")
            }

            Do(Step.issuerPrepare, over: issuers) { i in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(issuerState[i] == "waiting")
                issuerState[i].set("prepared")
                messages.insert(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i))))
            }

            Do(Step.issuerChooseToAbort, over: issuers) { i in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(issuerState[i] == "waiting")
                issuerState[i].set("aborted")
            }

            Do(Step.issuerReceivesIssue, over: issuers) { i in
                When(Functions(from: vouchers, to: SetExpr<String>.literal("phantom", "valid")).contains(voucherStatus))
                When(Functions(from: vouchers, to: SetExpr<String>.literal("init", "working")).contains(lifecyclePhase))
                When(issuerState[i] == "waiting")
                When(messages.contains(issueMessage))
                issuerState[i].set("issued")
            }

            Do(Step.issuerReceivesAbort, over: issuers) { i in
                When(allVouchersAreUnissued)
                When(allLifecyclesAreInitial)
                When(issuerState[i] == "waiting")
                When(messages.contains(abortMessage))
                issuerState[i].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: vouchers, to: SetExpr<String>.literal("phantom", "valid")).contains(voucherStatus)
                Functions(from: vouchers, to: SetExpr<String>.literal("init", "working")).contains(lifecyclePhase)
                Functions(from: holders, to: SetExpr<String>.literal("waiting", "prepared", "holding", "aborted")).contains(holderState)
                Functions(from: issuers, to: SetExpr<String>.literal("waiting", "prepared", "issued", "aborted")).contains(issuerState)
                SetExpr<String>.literal("init", "done").contains(transactionProviderState)
                preparedParticipants.isSubset(of: participants)
                messages.allSatisfy { message in
                    message == issueMessage || message == abortMessage
                        || holders.contains { holder in message == Message.first(HolderPrepared.expression(type: "Prepared", vh: holder)) }
                        || issuers.contains { issuer in message == Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: issuer))) }
                }
            }
            Invariant("VTPConsistent") {
                holders.allSatisfy { h in
                    issuers.allSatisfy { i in
                        !(holderState[h] == "holding" && issuerState[i] == "aborted")
                            && !(holderState[h] == "aborted" && issuerState[i] == "issued")
                    }
                }
            }
            let lifeCycle = Instance(of: VoucherLifeCycleModel.self) {
                Bind(\.vouchers, projecting: vouchers)
            }
            Refinement("VSpec", instance: lifeCycle) {
                Map(\.voucherStatus, projecting: voucherStatus)
                Map(\.lifecyclePhase, projecting: lifecyclePhase)
            }
            Validation("published") {
                Bind(vouchers, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(holders, to: Set<Participant>([.holder1, .holder2, .holder3]))
                Bind(issuers, to: Set<Participant>([.issuer1, .issuer2, .issuer3]))
            }.checkingDeadlock(false)
        }
    }
}

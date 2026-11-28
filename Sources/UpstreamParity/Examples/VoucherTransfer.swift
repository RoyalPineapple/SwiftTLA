// The transfer protocol moves a voucher between holders through prepare and completion steps.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/byihive/VoucherTransfer.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct VoucherTransferModel: Sendable {
    package enum Voucher: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, v3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .v1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Participant: String, CaseIterable, FiniteTLAValueDomain {
        case src1, src2, src3, dst1, dst2, dst3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .src1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct SourcePrepared: Hashable, Sendable {
        package let type: String
        package let vsh: Participant
    }
    package struct DestinationPrepared: Hashable, Sendable {
        package let type: String
        package let vdh: Participant
    }
    package struct Broadcast: Hashable, Sendable { package let type: String }
    package typealias OtherMessage = OneOf<DestinationPrepared, Broadcast>
    package typealias Message = OneOf<SourcePrepared, OtherMessage>
    private enum Step: String, CaseIterable {
        case providerRecordsPreparedPair = "VTPRcvPrepared"
        case providerTransfer = "VTPTransfer"
        case providerAbort = "VTPAbort"
        case sourcePrepare = "SHPrepare"
        case sourceChooseToAbort = "SHChooseToAbort"
        case sourceReceivesTransfer = "SHRcvTransferMsg"
        case sourceReceivesAbort = "SHRcvAbortMsg"
        case destinationPrepare = "DHPrepare"
        case destinationChooseToAbort = "DHChooseToAbort"
        case destinationReceivesTransfer = "DHRcvTransferMsg"
        case destinationReceivesAbort = "DHRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherTransfer") { scope in
            let vouchers = scope.parameter(tlaName: "V", as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let sourceHolders = scope.parameter(tlaName: "SH", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let destinationHolders = scope.parameter(tlaName: "DH", as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = sourceHolders.union(destinationHolders)
            let voucherStatus = scope.sharedVar(tlaName: "vState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "valid" })
            let lifecyclePhase = scope.sharedVar(tlaName: "vlcState", initial: Dictionary<Voucher, String>.mapping(over: vouchers) { _ in "working" })
            let sourceHolderState = scope.sharedVar(tlaName: "shState", initial: Dictionary<Participant, String>.mapping(over: sourceHolders) { _ in "holding" })
            let destinationHolderState = scope.sharedVar(tlaName: "dhState", initial: Dictionary<Participant, String>.mapping(over: destinationHolders) { _ in "waiting" })
            let transactionProviderState = scope.sharedVar(tlaName: "vtpState", initial: "init")
            let preparedParticipants = scope.sharedVar(tlaName: "vtpTPrepared", initial: Set<Participant>())
            let messages = scope.sharedVar(tlaName: "msgs", initial: Set<Message>())
            let transferMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Transfer")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            let allVouchersAreValid = Functions(from: vouchers, to: SetExpr<String>.literal("valid")).contains(voucherStatus)
            let allLifecyclesAreWorking = Functions(from: vouchers, to: SetExpr<String>.literal("working")).contains(lifecyclePhase)

            Do(Step.providerRecordsPreparedPair, over: participants, participants) { sh, dh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(transactionProviderState == "init")
                When(messages.contains(Message.first(SourcePrepared.expression(type: "Prepared", vsh: sh))))
                When(messages.contains(Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: dh)))))
                preparedParticipants.insert(sh)
                preparedParticipants.insert(dh)
            }

            Do(Step.providerTransfer, over: vouchers) { v in
                When(voucherStatus[v] == "valid")
                When(lifecyclePhase[v] == "working")
                When(transactionProviderState == "init")
                When(preparedParticipants == participants)
                transactionProviderState.set("done")
                messages.insert(transferMessage)
            }

            Do(Step.providerAbort, over: vouchers) { v in
                When(voucherStatus[v] == "valid")
                When(lifecyclePhase[v] == "working")
                When(transactionProviderState == "init")
                transactionProviderState.set("done")
                messages.insert(abortMessage)
            }

            Do(Step.sourcePrepare, over: sourceHolders) { sh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(sourceHolderState[sh] == "holding")
                sourceHolderState[sh].set("prepared")
                messages.insert(Message.first(SourcePrepared.expression(type: "Prepared", vsh: sh)))
            }

            Do(Step.sourceChooseToAbort, over: sourceHolders) { sh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(sourceHolderState[sh] == "holding")
                sourceHolderState[sh].set("aborted")
            }

            Do(Step.sourceReceivesTransfer, over: sourceHolders) { sh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(sourceHolderState[sh] == "holding")
                When(messages.contains(transferMessage))
                sourceHolderState[sh].set("transferred")
            }

            Do(Step.sourceReceivesAbort, over: sourceHolders) { sh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(sourceHolderState[sh] == "holding")
                When(messages.contains(abortMessage))
                sourceHolderState[sh].set("aborted")
            }

            Do(Step.destinationPrepare, over: destinationHolders) { dh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(destinationHolderState[dh] == "waiting")
                destinationHolderState[dh].set("prepared")
                messages.insert(Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: dh))))
            }

            Do(Step.destinationChooseToAbort, over: destinationHolders) { dh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(destinationHolderState[dh] == "waiting")
                destinationHolderState[dh].set("aborted")
            }

            Do(Step.destinationReceivesTransfer, over: destinationHolders) { dh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(destinationHolderState[dh] == "waiting")
                When(messages.contains(transferMessage))
                destinationHolderState[dh].set("holding")
            }

            Do(Step.destinationReceivesAbort, over: destinationHolders) { dh in
                When(allVouchersAreValid)
                When(allLifecyclesAreWorking)
                When(destinationHolderState[dh] == "waiting")
                When(messages.contains(abortMessage))
                destinationHolderState[dh].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: vouchers, to: SetExpr<String>.literal("valid")).contains(voucherStatus)
                Functions(from: vouchers, to: SetExpr<String>.literal("working")).contains(lifecyclePhase)
                Functions(from: sourceHolders, to: SetExpr<String>.literal("holding", "prepared", "transferred", "aborted")).contains(sourceHolderState)
                Functions(from: destinationHolders, to: SetExpr<String>.literal("waiting", "prepared", "holding", "aborted")).contains(destinationHolderState)
                SetExpr<String>.literal("init", "done").contains(transactionProviderState)
                preparedParticipants.isSubset(of: participants)
                messages.allSatisfy { message in
                    message == transferMessage || message == abortMessage
                        || sourceHolders.contains { sourceHolder in message == Message.first(SourcePrepared.expression(type: "Prepared", vsh: sourceHolder)) }
                        || destinationHolders.contains { destinationHolder in message == Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: destinationHolder))) }
                }
            }
            Invariant("VTPConsistent") {
                sourceHolders.allSatisfy { sh in
                    destinationHolders.allSatisfy { dh in
                        !(sourceHolderState[sh] == "transferred" && destinationHolderState[dh] == "aborted")
                            && !(sourceHolderState[sh] == "aborted" && destinationHolderState[dh] == "holding")
                    }
                }
            }
            Validation("published") {
                Bind(vouchers, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(sourceHolders, to: Set<Participant>([.src1, .src2, .src3]))
                Bind(destinationHolders, to: Set<Participant>([.dst1, .dst2, .dst3]))
            }.checkingDeadlock(false)
        }
    }
}

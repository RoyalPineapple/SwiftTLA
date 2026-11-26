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
        case providerRcvPrepared = "VTPRcvPrepared"
        case providerTransfer = "VTPTransfer"
        case providerAbort = "VTPAbort"
        case sourcePrepare = "SHPrepare"
        case sourceChooseToAbort = "SHChooseToAbort"
        case sourceRcvTransferMsg = "SHRcvTransferMsg"
        case sourceRcvAbortMsg = "SHRcvAbortMsg"
        case destinationPrepare = "DHPrepare"
        case destinationChooseToAbort = "DHChooseToAbort"
        case destinationRcvTransferMsg = "DHRcvTransferMsg"
        case destinationRcvAbortMsg = "DHRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherTransfer") { scope in
            let V = scope.parameter(as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let SH = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let DH = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = SH.union(DH)
            let vState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "valid" })
            let vlcState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "working" })
            let shState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: SH) { _ in "holding" })
            let dhState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: DH) { _ in "waiting" })
            let vtpState = scope.sharedVar(initial: "init")
            let vtpTPrepared = scope.sharedVar(initial: Set<Participant>())
            let msgs = scope.sharedVar(initial: Set<Message>())
            let transferMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Transfer")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            Do(Step.providerRcvPrepared, over: participants, participants) { sh, dh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(vtpState == "init")
                When(msgs.contains(Message.first(SourcePrepared.expression(type: "Prepared", vsh: sh))))
                When(msgs.contains(Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: dh)))))
                vtpTPrepared.insert(sh)
                vtpTPrepared.insert(dh)
            }

            Do(Step.providerTransfer, over: V) { v in
                When(vState[v] == "valid")
                When(vlcState[v] == "working")
                When(vtpState == "init")
                When(vtpTPrepared == participants)
                vtpState.set("done")
                msgs.insert(transferMessage)
            }

            Do(Step.providerAbort, over: V) { v in
                When(vState[v] == "valid")
                When(vlcState[v] == "working")
                When(vtpState == "init")
                vtpState.set("done")
                msgs.insert(abortMessage)
            }

            Do(Step.sourcePrepare, over: SH) { sh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(shState[sh] == "holding")
                shState[sh].set("prepared")
                msgs.insert(Message.first(SourcePrepared.expression(type: "Prepared", vsh: sh)))
            }

            Do(Step.sourceChooseToAbort, over: SH) { sh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(shState[sh] == "holding")
                shState[sh].set("aborted")
            }

            Do(Step.sourceRcvTransferMsg, over: SH) { sh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(shState[sh] == "holding")
                When(msgs.contains(transferMessage))
                shState[sh].set("transferred")
            }

            Do(Step.sourceRcvAbortMsg, over: SH) { sh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(shState[sh] == "holding")
                When(msgs.contains(abortMessage))
                shState[sh].set("aborted")
            }

            Do(Step.destinationPrepare, over: DH) { dh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(dhState[dh] == "waiting")
                dhState[dh].set("prepared")
                msgs.insert(Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: dh))))
            }

            Do(Step.destinationChooseToAbort, over: DH) { dh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(dhState[dh] == "waiting")
                dhState[dh].set("aborted")
            }

            Do(Step.destinationRcvTransferMsg, over: DH) { dh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(dhState[dh] == "waiting")
                When(msgs.contains(transferMessage))
                dhState[dh].set("holding")
            }

            Do(Step.destinationRcvAbortMsg, over: DH) { dh in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(dhState[dh] == "waiting")
                When(msgs.contains(abortMessage))
                dhState[dh].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState)
                Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState)
                Functions(from: SH, to: SetExpr<String>.literal("holding", "prepared", "transferred", "aborted")).contains(shState)
                Functions(from: DH, to: SetExpr<String>.literal("waiting", "prepared", "holding", "aborted")).contains(dhState)
                SetExpr<String>.literal("init", "done").contains(vtpState)
                vtpTPrepared.isSubset(of: participants)
                msgs.allSatisfy { message in
                    message == transferMessage || message == abortMessage
                        || SH.contains { p in message == Message.first(SourcePrepared.expression(type: "Prepared", vsh: p)) }
                        || DH.contains { p in message == Message.second(OtherMessage.first(DestinationPrepared.expression(type: "Prepared", vdh: p))) }
                }
            }
            Invariant("VTPConsistent") {
                SH.allSatisfy { sh in
                    DH.allSatisfy { dh in
                        !(shState[sh] == "transferred" && dhState[dh] == "aborted")
                            && !(shState[sh] == "aborted" && dhState[dh] == "holding")
                    }
                }
            }
            Validation("published") {
                Bind(V, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(SH, to: Set<Participant>([.src1, .src2, .src3]))
                Bind(DH, to: Set<Participant>([.dst1, .dst2, .dst3]))
            }.checkingDeadlock(false)
        }
    }
}

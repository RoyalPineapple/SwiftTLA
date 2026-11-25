import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct VoucherCancelModel: Sendable {
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
        case providerRcvPrepared = "VTPRcvPrepared"
        case providerCancel = "VTPCancel"
        case providerAbort = "VTPAbort"
        case holderPrepare = "HPrepare"
        case holderChooseToAbort = "HChooseToAbort"
        case holderRcvCancelMsg = "HRcvCancelMsg"
        case holderRcvAbortMsg = "HRcvAbortMsg"
        case issuerPrepare = "IPrepare"
        case issuerChooseToAbort = "IChooseToAbort"
        case issuerRcvCancelMsg = "IRcvCancelMsg"
        case issuerRcvAbortMsg = "IRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherCancel") { scope in
            let V = scope.parameter(as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let H = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let I = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = H.union(I)
            let vState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "valid" })
            let vlcState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "working" })
            let hState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: H) { _ in "holding" })
            let iState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: I) { _ in "waiting" })
            let vtpState = scope.sharedVar(initial: "init")
            let vtpCPrepared = scope.sharedVar(initial: Set<Participant>())
            let msgs = scope.sharedVar(initial: Set<Message>())
            let cancelMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Cancel")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            Do(Step.providerRcvPrepared, over: participants, participants) { h, i in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(vtpState == "init")
                When(msgs.contains(Message.first(HolderPrepared.expression(type: "Prepared", vh: h))))
                When(msgs.contains(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i)))))
                vtpCPrepared.insert(h)
                vtpCPrepared.insert(i)
            }

            Do(Step.providerCancel, over: V) { v in
                When(vState[v] == "valid")
                When(vlcState[v] == "working")
                When(vtpState == "init")
                When(vtpCPrepared == participants)
                vtpState.set("done")
                vState[v].set("cancelled")
                vlcState[v].set("done")
                msgs.insert(cancelMessage)
            }

            Do(Step.providerAbort, over: V) { v in
                When(vState[v] == "valid")
                When(vlcState[v] == "working")
                When(vtpState == "init")
                vtpState.set("done")
                msgs.insert(abortMessage)
            }

            Do(Step.holderPrepare, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(hState[h] == "holding")
                hState[h].set("prepared")
                msgs.insert(Message.first(HolderPrepared.expression(type: "Prepared", vh: h)))
            }

            Do(Step.holderChooseToAbort, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(hState[h] == "holding")
                hState[h].set("aborted")
            }

            Do(Step.holderRcvCancelMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid", "cancelled")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState))
                When(hState[h] == "holding")
                When(msgs.contains(cancelMessage))
                hState[h].set("cancelled")
            }

            Do(Step.holderRcvAbortMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(hState[h] == "holding")
                When(msgs.contains(abortMessage))
                hState[h].set("aborted")
            }

            Do(Step.issuerPrepare, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(iState[i] == "waiting")
                iState[i].set("prepared")
                msgs.insert(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i))))
            }

            Do(Step.issuerChooseToAbort, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(iState[i] == "waiting")
                iState[i].set("aborted")
            }

            Do(Step.issuerRcvCancelMsg, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("valid", "cancelled")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState))
                When(iState[i] == "waiting")
                When(msgs.contains(cancelMessage))
                iState[i].set("cancelled")
            }

            Do(Step.issuerRcvAbortMsg, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(iState[i] == "waiting")
                When(msgs.contains(abortMessage))
                iState[i].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: V, to: SetExpr<String>.literal("valid", "cancelled")).contains(vState)
                Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState)
                Functions(from: H, to: SetExpr<String>.literal("holding", "prepared", "cancelled", "aborted")).contains(hState)
                Functions(from: I, to: SetExpr<String>.literal("waiting", "prepared", "cancelled", "aborted")).contains(iState)
                SetExpr<String>.literal("init", "done").contains(vtpState)
                vtpCPrepared.isSubset(of: participants)
                msgs.allSatisfy { message in
                    message == cancelMessage || message == abortMessage
                        || H.contains { p in message == Message.first(HolderPrepared.expression(type: "Prepared", vh: p)) }
                        || I.contains { p in message == Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: p))) }
                }
            }
            Invariant("VTPConsistent") {
                H.allSatisfy { h in
                    I.allSatisfy { i in
                        !(hState[h] == "cancelled" && iState[i] == "aborted")
                            && !(hState[h] == "aborted" && iState[i] == "cancelled")
                    }
                }
            }
            Validation("published") {
                Bind(V, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(H, to: Set<Participant>([.holder1, .holder2, .holder3]))
                Bind(I, to: Set<Participant>([.issuer1, .issuer2, .issuer3]))
            }.checkingDeadlock(false)
        }
    }
}

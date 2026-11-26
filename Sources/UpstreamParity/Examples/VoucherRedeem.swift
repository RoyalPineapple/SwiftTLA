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
        case providerRcvPrepared = "VTPRcvPrepared"
        case providerRedeem = "VTPRedeem"
        case providerAbort = "VTPAbort"
        case holderPrepare = "HPrepare"
        case holderChooseToAbort = "HChooseToAbort"
        case holderRcvRedeemMsg = "HRcvRedeemMsg"
        case holderRcvAbortMsg = "HRcvAbortMsg"
        case collectorPrepare = "CPrepare"
        case collectorChooseToAbort = "CChooseToAbort"
        case collectorRcvRedeemMsg = "CRcvRedeemMsg"
        case collectorRcvAbortMsg = "CRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherRedeem") { scope in
            let V = scope.parameter(as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let H = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let C = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = H.union(C)
            let vState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "valid" })
            let vlcState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "working" })
            let hState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: H) { _ in "holding" })
            let cState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: C) { _ in "waiting" })
            let vtpState = scope.sharedVar(initial: "init")
            let vtpRPrepared = scope.sharedVar(initial: Set<Participant>())
            let msgs = scope.sharedVar(initial: Set<Message>())
            let redeemMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Redeem")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            Do(Step.providerRcvPrepared, over: participants, participants) { h, c in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(vtpState == "init")
                When(msgs.contains(Message.first(HolderPrepared.expression(type: "Prepared", vh: h))))
                When(msgs.contains(Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: c)))))
                vtpRPrepared.insert(h)
                vtpRPrepared.insert(c)
            }

            Do(Step.providerRedeem, over: V) { v in
                When(vState[v] == "valid")
                When(vlcState[v] == "working")
                When(vtpState == "init")
                When(vtpRPrepared == participants)
                vtpState.set("done")
                vState[v].set("redeemed")
                vlcState[v].set("done")
                msgs.insert(redeemMessage)
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

            Do(Step.holderRcvRedeemMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid", "redeemed")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState))
                When(hState[h] == "holding")
                When(msgs.contains(redeemMessage))
                hState[h].set("redeemed")
            }

            Do(Step.holderRcvAbortMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(hState[h] == "holding")
                When(msgs.contains(abortMessage))
                hState[h].set("aborted")
            }

            Do(Step.collectorPrepare, over: C) { c in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(cState[c] == "waiting")
                cState[c].set("prepared")
                msgs.insert(Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: c))))
            }

            Do(Step.collectorChooseToAbort, over: C) { c in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(cState[c] == "waiting")
                cState[c].set("aborted")
            }

            Do(Step.collectorRcvRedeemMsg, over: C) { c in
                When(Functions(from: V, to: SetExpr<String>.literal("valid", "redeemed")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState))
                When(cState[c] == "waiting")
                When(msgs.contains(redeemMessage))
                cState[c].set("redeemed")
            }

            Do(Step.collectorRcvAbortMsg, over: C) { c in
                When(Functions(from: V, to: SetExpr<String>.literal("valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("working")).contains(vlcState))
                When(cState[c] == "waiting")
                When(msgs.contains(abortMessage))
                cState[c].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: V, to: SetExpr<String>.literal("valid", "redeemed")).contains(vState)
                Functions(from: V, to: SetExpr<String>.literal("working", "done")).contains(vlcState)
                Functions(from: H, to: SetExpr<String>.literal("holding", "prepared", "redeemed", "aborted")).contains(hState)
                Functions(from: C, to: SetExpr<String>.literal("waiting", "prepared", "redeemed", "aborted")).contains(cState)
                SetExpr<String>.literal("init", "done").contains(vtpState)
                vtpRPrepared.isSubset(of: participants)
                msgs.allSatisfy { message in
                    message == redeemMessage || message == abortMessage
                        || H.contains { p in message == Message.first(HolderPrepared.expression(type: "Prepared", vh: p)) }
                        || C.contains { p in message == Message.second(OtherMessage.first(CollectorPrepared.expression(type: "Prepared", vc: p))) }
                }
            }
            Invariant("VTPConsistent") {
                H.allSatisfy { h in
                    C.allSatisfy { c in
                        !(hState[h] == "redeemed" && cState[c] == "aborted")
                            && !(hState[h] == "aborted" && cState[c] == "redeemed")
                    }
                }
            }
            Validation("published") {
                Bind(V, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(H, to: Set<Participant>([.holder1, .holder2, .holder3]))
                Bind(C, to: Set<Participant>([.collector1, .collector2, .collector3]))
            }.checkingDeadlock(false)
        }
    }
}

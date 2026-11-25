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
        case providerRcvPrepared = "VTPRcvPrepared"
        case providerIssue = "VTPIssue"
        case providerAbort = "VTPAbort"
        case holderPrepare = "HPrepare"
        case holderChooseToAbort = "HChooseToAbort"
        case holderRcvIssueMsg = "HRcvIssueMsg"
        case holderRcvAbortMsg = "HRcvAbortMsg"
        case issuerPrepare = "IPrepare"
        case issuerChooseToAbort = "IChooseToAbort"
        case issuerRcvIssueMsg = "IRcvIssueMsg"
        case issuerRcvAbortMsg = "IRcvAbortMsg"
    }
    package static var spec: TLASpec {
        #spec("VoucherIssue") { scope in
            let V = scope.parameter(as: Set<Voucher>.self, in: Subsets(of: Voucher.all.assuming(Set<Voucher>.self)))
            let H = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let I = scope.parameter(as: Set<Participant>.self, in: Subsets(of: Participant.all.assuming(Set<Participant>.self)))
            let participants = H.union(I)
            let vState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "phantom" })
            let vlcState = scope.sharedVar(initial: Dictionary<Voucher, String>.mapping(over: V) { _ in "init" })
            let hState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: H) { _ in "waiting" })
            let iState = scope.sharedVar(initial: Dictionary<Participant, String>.mapping(over: I) { _ in "waiting" })
            let vtpState = scope.sharedVar(initial: "init")
            let vtpIPrepared = scope.sharedVar(initial: Set<Participant>())
            let msgs = scope.sharedVar(initial: Set<Message>())
            let issueMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Issue")))
            let abortMessage: Message = Message.second(OtherMessage.second(Broadcast(type: "Abort")))

            Do(Step.providerRcvPrepared, over: participants, participants) { h, i in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(vtpState == "init")
                When(msgs.contains(Message.first(HolderPrepared.expression(type: "Prepared", vh: h))))
                When(msgs.contains(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i)))))
                vtpIPrepared.insert(h)
                vtpIPrepared.insert(i)
            }

            Do(Step.providerIssue, over: V) { v in
                When(vState[v] == "phantom")
                When(vlcState[v] == "init")
                When(vtpState == "init")
                When(vtpIPrepared == participants)
                vtpState.set("done")
                vState[v].set("valid")
                vlcState[v].set("working")
                msgs.insert(issueMessage)
            }

            Do(Step.providerAbort, over: V) { v in
                When(vState[v] == "phantom")
                When(vlcState[v] == "init")
                When(vtpState == "init")
                vtpState.set("done")
                msgs.insert(abortMessage)
            }

            Do(Step.holderPrepare, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(hState[h] == "waiting")
                hState[h].set("prepared")
                msgs.insert(Message.first(HolderPrepared.expression(type: "Prepared", vh: h)))
            }

            Do(Step.holderChooseToAbort, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(hState[h] == "waiting")
                hState[h].set("aborted")
            }

            Do(Step.holderRcvIssueMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom", "valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init", "working")).contains(vlcState))
                When(hState[h] == "waiting")
                When(msgs.contains(issueMessage))
                hState[h].set("holding")
            }

            Do(Step.holderRcvAbortMsg, over: H) { h in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(hState[h] == "waiting")
                When(msgs.contains(abortMessage))
                hState[h].set("aborted")
            }

            Do(Step.issuerPrepare, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(iState[i] == "waiting")
                iState[i].set("prepared")
                msgs.insert(Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: i))))
            }

            Do(Step.issuerChooseToAbort, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(iState[i] == "waiting")
                iState[i].set("aborted")
            }

            Do(Step.issuerRcvIssueMsg, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom", "valid")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init", "working")).contains(vlcState))
                When(iState[i] == "waiting")
                When(msgs.contains(issueMessage))
                iState[i].set("issued")
            }

            Do(Step.issuerRcvAbortMsg, over: I) { i in
                When(Functions(from: V, to: SetExpr<String>.literal("phantom")).contains(vState))
                When(Functions(from: V, to: SetExpr<String>.literal("init")).contains(vlcState))
                When(iState[i] == "waiting")
                When(msgs.contains(abortMessage))
                iState[i].set("aborted")
            }

            Invariant("VTPTypeOK") {
                Functions(from: V, to: SetExpr<String>.literal("phantom", "valid")).contains(vState)
                Functions(from: V, to: SetExpr<String>.literal("init", "working")).contains(vlcState)
                Functions(from: H, to: SetExpr<String>.literal("waiting", "prepared", "holding", "aborted")).contains(hState)
                Functions(from: I, to: SetExpr<String>.literal("waiting", "prepared", "issued", "aborted")).contains(iState)
                SetExpr<String>.literal("init", "done").contains(vtpState)
                vtpIPrepared.isSubset(of: participants)
                msgs.allSatisfy { message in
                    message == issueMessage || message == abortMessage
                        || H.contains { p in message == Message.first(HolderPrepared.expression(type: "Prepared", vh: p)) }
                        || I.contains { p in message == Message.second(OtherMessage.first(IssuerPrepared.expression(type: "Prepared", vi: p))) }
                }
            }
            Invariant("VTPConsistent") {
                H.allSatisfy { h in
                    I.allSatisfy { i in
                        !(hState[h] == "holding" && iState[i] == "aborted")
                            && !(hState[h] == "aborted" && iState[i] == "issued")
                    }
                }
            }
            let lifeCycle = Instance(of: VoucherLifeCycleModel.self) {
                Bind(\.V, projecting: V)
            }
            lifeCycle
            let VSpec = Refinement(instance: lifeCycle) {
                Map(\.vState, projecting: vState)
                Map(\.vlcState, projecting: vlcState)
            }
            VSpec
            Validation("published") {
                Bind(V, to: Set<Voucher>([.v1, .v2, .v3]))
                Bind(H, to: Set<Participant>([.holder1, .holder2, .holder3]))
                Bind(I, to: Set<Participant>([.issuer1, .issuer2, .issuer3]))
            }.checkingDeadlock(false)
        }
    }
}

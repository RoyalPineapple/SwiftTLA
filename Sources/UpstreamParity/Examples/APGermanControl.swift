// Directory-based cache coherence with two concrete nodes.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/GermanProtocol/GermanControl.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APGermanControlModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, noNode, other
        case ap1 = "n1_OF_NODE", ap2 = "n2_OF_NODE"
        case apNoNode = "noNode_OF_NODE", apOther = "other_OF_NODE"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .n1 }
        package var tlaValue: TLAValue {
            switch self {
            case .n1, .n2, .noNode, .other: .constant(rawValue)
            case .ap1, .ap2, .apNoNode, .apOther: .string(rawValue)
            }
        }
    }

    private enum Step: String, CaseIterable {
        case sendReq = "SendReq", recvReq = "RecvReq", sendInv = "SendInv", sendInvAck = "SendInvAck"
        case recvInvAck = "RecvInvAck", sendGnt = "SendGnt", recvGnt = "RecvGnt"
    }

    package static var spec: TLASpec {
        #spec("GermanControl") { scope in
            let nodes = scope.parameter(as: Set<Node>.self, in: Set<Set<Node>>([Set<Node>([Node.n1, Node.n2]), Set<Node>([Node.ap1, Node.ap2])]))
            let noNode = scope.parameter(as: Node.self, in: Set<Node>([Node.noNode, Node.apNoNode]))
            Assume(!nodes.contains(noNode))
            let other = scope.parameter(as: Node.self, in: Set<Node>([Node.other, Node.apOther]))
            Assume(!nodes.contains(other) && other != noNode)
            let requests = Set<String>(["ReqS", "ReqE"])
            let grants = Set<String>(["GntS", "GntE"])
            let cache = scope.sharedVar(initial: Dictionary<Node, String>.mapping(over: nodes) { _ in "I" })
            let chan1 = scope.sharedVar(initial: Dictionary<Node, String>.mapping(over: nodes) { _ in "Empty" })
            let chan2 = scope.sharedVar(initial: Dictionary<Node, String>.mapping(over: nodes) { _ in "Empty" })
            let chan3 = scope.sharedVar(initial: Dictionary<Node, String>.mapping(over: nodes) { _ in "Empty" })
            let invSet = scope.sharedVar(initial: Set<Node>())
            let shrSet = scope.sharedVar(initial: Set<Node>())
            let exGntd = scope.sharedVar(initial: false)
            let curCmd = scope.sharedVar(initial: "Empty")
            let curPtr = scope.sharedVar(initial: noNode)

            Do(Step.sendReq, over: nodes) { i in
                When(chan1[i] == "Empty")
                With(requests) { c in
                    When(cache[i] == "I" || (c == "ReqE" && cache[i] == "S"))
                    chan1[i].set(c)
                }
            }
            Do(Step.recvReq, over: nodes) { i in
                When(curCmd == "Empty" && requests.contains(chan1[i]))
                curCmd.set(chan1[i])
                curPtr.set(i)
                chan1[i].set("Empty")
                invSet.set(shrSet)
            }
            Do(Step.sendInv, over: nodes) { i in
                When(chan2[i] == "Empty" && invSet.contains(i))
                When(curCmd == "ReqE" || (curCmd == "ReqS" && exGntd))
                chan2[i].set("Inv")
                invSet.remove(i)
            }
            Do(Step.sendInvAck, over: nodes) { i in
                When(chan2[i] == "Inv" && chan3[i] == "Empty")
                chan2[i].set("Empty")
                chan3[i].set("InvAck")
                cache[i].set("I")
            }
            Do(Step.recvInvAck, over: nodes) { i in
                When(chan3[i] == "InvAck" && curCmd != "Empty")
                chan3[i].set("Empty")
                shrSet.remove(i)
                exGntd.set(false)
            }
            Do(Step.sendGnt, over: nodes) { i in
                When(requests.contains(curCmd) && curPtr == i && chan2[i] == "Empty")
                When(!exGntd && (curCmd != "ReqE" || shrSet.isEmpty))
                chan2[i].set(If(curCmd == "ReqS", then: "GntS", else: "GntE"))
                shrSet.insert(i)
                exGntd.set(curCmd == "ReqE")
                curCmd.set("Empty")
                curPtr.set(noNode)
            }
            Do(Step.recvGnt, over: nodes) { i in
                When(grants.contains(chan2[i]))
                cache[i].set(If(chan2[i] == "GntS", then: "S", else: "E"))
                chan2[i].set("Empty")
            }

            let TypeOK = Invariant()
            let Coherence = Invariant()
            TypeOK {
                Functions(from: nodes, to: Set<String>(["I", "S", "E"])).contains(cache)
                Functions(from: nodes, to: Set<String>(["Empty", "ReqS", "ReqE"])).contains(chan1)
                Functions(from: nodes, to: Set<String>(["Empty", "Inv", "GntS", "GntE"])).contains(chan2)
                Functions(from: nodes, to: Set<String>(["Empty", "InvAck"])).contains(chan3)
                invSet.isSubset(of: nodes) && shrSet.isSubset(of: nodes)
                Set<Bool>([false, true]).contains(exGntd)
                Set<String>(["Empty", "ReqS", "ReqE"]).contains(curCmd)
                nodes.contains(curPtr) || curPtr == noNode
            }
            Coherence {
                nodes.allSatisfy { i in nodes.allSatisfy { j in
                    i == j || ((cache[i] != "E" || cache[j] == "I") &&
                            (cache[i] != "S" || cache[j] == "I" || cache[j] == "S"))
                } }
            }
            let abstract = Instance(of: GermanCMPWithMutexModel.self) {
                Bind(\.nodes, projecting: nodes)
                Bind(\.noNode, projecting: noNode)
                Bind(\.other, projecting: other)
            }
            Refinement("Refinement", instance: abstract, behavior: .initialAndNext) {
                Map(\.cache, projecting: cache)
                Map(\.chan1, projecting: chan1)
                Map(\.chan2, projecting: chan2)
                Map(\.chan3, projecting: chan3)
                Map(\.invSet, projecting: invSet)
                Map(\.shrSet, projecting: shrSet)
                Map(\.exGntd, from: exGntd)
                Map(\.curCmd, projecting: curCmd)
                Map(\.curPtr, projecting: curPtr)
            }
            let nodeSymmetry = Symmetry(nodes)
            Validation("Upstream") {
                Bind(nodes, to: Set<Node>([Node.ap1, Node.ap2]))
                Bind(noNode, to: Node.apNoNode)
                Bind(other, to: Node.apOther)
            }.checking(only: [TypeOK, Coherence])
            Validation("MCGermanControl") {
                Bind(nodes, to: Set<Node>([Node.n1, Node.n2]))
                Bind(noNode, to: Node.noNode)
                Bind(other, to: Node.other)
            }.usingSymmetry(nodeSymmetry)
        }
    }
}

// Two caches exchange grants, invalidations and data. A writeback from the exclusive holder updates memory.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/GermanProtocol/GermanData.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APGermanDataModel: Sendable {
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

    package enum Payload: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2, noData
        case ap1 = "d1_OF_DATA", ap2 = "d2_OF_DATA", apNoData = "noData_OF_DATA"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .noData }
        package var tlaValue: TLAValue {
            switch self {
            case .d1, .d2, .noData: .constant(rawValue)
            case .ap1, .ap2, .apNoData: .string(rawValue)
            }
        }
    }

    package struct Line: Sendable, Hashable {
        package let state: String
        package let data: Payload
    }
    package struct Message: Sendable, Hashable {
        package let cmd: String
        package let data: Payload
    }

    private enum Step: String, CaseIterable {
        case store = "Store"
        case sendReq = "SendReq", recvReq = "RecvReq", sendInv = "SendInv", sendInvAck = "SendInvAck"
        case recvInvAck = "RecvInvAck", sendGnt = "SendGnt", recvGnt = "RecvGnt"
    }

    package static var spec: TLASpec {
        #spec("GermanData") { scope in
            let nodes = scope.parameter(as: Set<Node>.self, in: Set<Set<Node>>([Set<Node>([Node.n1, Node.n2]), Set<Node>([Node.ap1, Node.ap2])]))
            let noNode = scope.parameter(as: Node.self, in: Set<Node>([Node.noNode, Node.apNoNode]))
            Assume(!nodes.contains(noNode))
            let data = scope.parameter(as: Set<Payload>.self, in: Set<Set<Payload>>([Set<Payload>([Payload.d1, Payload.d2]), Set<Payload>([Payload.ap1, Payload.ap2])]))
            let noData = scope.parameter(as: Payload.self, in: Set<Payload>([Payload.noData, Payload.apNoData]))
            Assume(!data.contains(noData))
            let payloads = data.inserting(noData)
            let requests = Set<String>(["ReqS", "ReqE"])
            let grants = Set<String>(["GntS", "GntE"])
            let cache = scope.sharedVar(initial: Dictionary<Node, Line>.mapping(over: nodes) { _ in Line.expression(state: "I", data: noData) })
            let chan1 = scope.sharedVar(initial: Dictionary<Node, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let chan2 = scope.sharedVar(initial: Dictionary<Node, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let chan3 = scope.sharedVar(initial: Dictionary<Node, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let invSet = scope.sharedVar(initial: Set<Node>())
            let shrSet = scope.sharedVar(initial: Set<Node>())
            let exGntd = scope.sharedVar(initial: false)
            let curCmd = scope.sharedVar(initial: "Empty")
            let curPtr = scope.sharedVar(initial: noNode)

            let memData = scope.sharedVar(initiallyIn: data)
            let auxData = scope.sharedVar(initial: memData)

            Do(Step.store, over: nodes, data) { i, d in
                When(cache[i].state == "E")
                cache[i].data.set(d)
                auxData.set(d)
            }
            Do(Step.sendReq, over: nodes) { i in
                When(chan1[i].cmd == "Empty")
                With(requests) { c in
                    When(cache[i].state == "I" || (c == "ReqE" && cache[i].state == "S"))
                    chan1[i].cmd.set(c)
                }
            }
            Do(Step.recvReq, over: nodes) { i in
                When(curCmd == "Empty" && requests.contains(chan1[i].cmd))
                curCmd.set(chan1[i].cmd)
                curPtr.set(i)
                chan1[i].cmd.set("Empty")
                invSet.set(shrSet)
            }
            Do(Step.sendInv, over: nodes) { i in
                When(chan2[i].cmd == "Empty" && invSet.contains(i))
                When(curCmd == "ReqE" || (curCmd == "ReqS" && exGntd))
                chan2[i].cmd.set("Inv")
                invSet.remove(i)
            }
            Do(Step.sendInvAck, over: nodes) { i in
                When(chan2[i].cmd == "Inv" && chan3[i].cmd == "Empty")
                chan2[i].cmd.set("Empty")
                chan2[i].data.set(noData)
                chan3[i].cmd.set("InvAck")
                chan3[i].data.set(If(cache[i].state == "E", then: cache[i].data, else: noData))
                cache[i].state.set("I")
                cache[i].data.set(noData)
            }
            Do(Step.recvInvAck, over: nodes) { i in
                When(chan3[i].cmd == "InvAck" && curCmd != "Empty")
                chan3[i].cmd.set("Empty")
                shrSet.remove(i)
                If(exGntd) {
                    memData.set(chan3[i].data)
                    chan3[i].data.set(noData)
                    exGntd.set(false)
                }
            }
            Do(Step.sendGnt, over: nodes) { i in
                When(requests.contains(curCmd) && curPtr == i && chan2[i].cmd == "Empty")
                When(!exGntd && (curCmd != "ReqE" || shrSet.isEmpty))
                chan2[i].cmd.set(If(curCmd == "ReqS", then: "GntS", else: "GntE"))
                chan2[i].data.set(memData)
                shrSet.insert(i)
                exGntd.set(curCmd == "ReqE")
                curCmd.set("Empty")
                curPtr.set(noNode)
            }
            Do(Step.recvGnt, over: nodes) { i in
                When(grants.contains(chan2[i].cmd))
                cache[i].state.set(If(chan2[i].cmd == "GntS", then: "S", else: "E"))
                cache[i].data.set(chan2[i].data)
                chan2[i].cmd.set("Empty")
                chan2[i].data.set(noData)
            }

            let TypeOK = Invariant()
            TypeOK {
                cache.keys == nodes && nodes.allSatisfy { i in
                    Set<String>(["I", "S", "E"]).contains(cache[i].state) && payloads.contains(cache[i].data)
                }
                chan1.keys == nodes && nodes.allSatisfy { i in
                    Set<String>(["Empty", "ReqS", "ReqE"]).contains(chan1[i].cmd) && payloads.contains(chan1[i].data)
                }
                chan2.keys == nodes && nodes.allSatisfy { i in
                    Set<String>(["Empty", "Inv", "GntS", "GntE"]).contains(chan2[i].cmd) && payloads.contains(chan2[i].data)
                }
                chan3.keys == nodes && nodes.allSatisfy { i in
                    Set<String>(["Empty", "InvAck"]).contains(chan3[i].cmd) && payloads.contains(chan3[i].data)
                }
                invSet.isSubset(of: nodes) && shrSet.isSubset(of: nodes)
                Set<Bool>([false, true]).contains(exGntd)
                Set<String>(["Empty", "ReqS", "ReqE"]).contains(curCmd)
                nodes.contains(curPtr) || curPtr == noNode
                data.contains(memData) && data.contains(auxData)
            }
            let Coherence = Invariant()
            Coherence {
                nodes.allSatisfy { i in nodes.allSatisfy { j in
                    i == j || ((cache[i].state != "E" || cache[j].state == "I") &&
                            (cache[i].state != "S" || cache[j].state == "I" || cache[j].state == "S"))
                } }
            }
            let DataProp = Invariant()
            DataProp {
                exGntd || memData == auxData
                nodes.allSatisfy { i in cache[i].state == "I" || cache[i].data == auxData }
            }
            let TransactionConsistency = Invariant()
            TransactionConsistency { (curCmd == "Empty") == (curPtr == noNode) }
            let DirectoryAccurate = Invariant()
            DirectoryAccurate {
                nodes.allSatisfy { i in (cache[i].state != "S" && cache[i].state != "E") || shrSet.contains(i) }
            }
            let ExclusiveIsolation = Invariant()
            ExclusiveIsolation {
                nodes.allSatisfy { i in cache[i].state != "E" || (exGntd && nodes.allSatisfy { j in
                    i == j || (cache[j].state == "I" && !grants.contains(chan2[j].cmd) && chan3[j].cmd != "InvAck")
                }) }
            }
            let WritebackCarriesLatest = Invariant()
            WritebackCarriesLatest {
                nodes.allSatisfy { i in
                    chan3[i].cmd != "InvAck" || curCmd == "Empty" || !exGntd ||
                        (chan3[i].data == auxData && nodes.allSatisfy { j in
                            i == j || (cache[j].state != "E" && chan2[j].cmd != "GntE" && chan3[j].cmd != "InvAck")
                        })
                }
            }
            let abstract = Instance(of: APGermanControlModel.self) {
                Bind(\.nodes, projecting: nodes)
                Bind(\.noNode, projecting: noNode)
                Bind(\.other, projecting: Node.other)
            }
            Refinement("Refinement", instance: abstract, behavior: .initialAndNext) {
                Map(\.cache, projecting: Dictionary<Node, String>.mapping(over: nodes) { i in cache[i].state })
                Map(\.chan1, projecting: Dictionary<Node, String>.mapping(over: nodes) { i in chan1[i].cmd })
                Map(\.chan2, projecting: Dictionary<Node, String>.mapping(over: nodes) { i in chan2[i].cmd })
                Map(\.chan3, projecting: Dictionary<Node, String>.mapping(over: nodes) { i in chan3[i].cmd })
                Map(\.invSet, projecting: invSet)
                Map(\.shrSet, projecting: shrSet)
                Map(\.exGntd, from: exGntd)
                Map(\.curCmd, projecting: curCmd)
                Map(\.curPtr, projecting: curPtr)
            }
            let symmetry = Symmetry(independently: nodes, data)
            Validation("Upstream") {
                Bind(nodes, to: Set<Node>([Node.ap1, Node.ap2]))
                Bind(noNode, to: Node.apNoNode)
                Bind(data, to: Set<Payload>([Payload.ap1, Payload.ap2]))
                Bind(noData, to: Payload.apNoData)
            }.checking(only: [TypeOK, Coherence, DataProp, TransactionConsistency, DirectoryAccurate, ExclusiveIsolation, WritebackCarriesLatest])
            Validation("MCGermanData") {
                Bind(nodes, to: Set<Node>([Node.n1, Node.n2]))
                Bind(noNode, to: Node.noNode)
                Bind(data, to: Set<Payload>([Payload.d1, Payload.d2]))
                Bind(noData, to: Payload.noData)
            }.usingSymmetry(symmetry)
        }
    }
}

// Two caches exchange grants, invalidations and data. A writeback from the exclusive holder updates memory.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/GermanProtocol/GermanData.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APGermanDataModel: Sendable {
    package struct Line: Sendable, Hashable {
        package let state: String
        package let data: String
    }
    package struct Message: Sendable, Hashable {
        package let cmd: String
        package let data: String
    }

    private enum Step: String, CaseIterable {
        case store = "Store"
        case sendReq = "SendReq", recvReq = "RecvReq", sendInv = "SendInv", sendInvAck = "SendInvAck"
        case recvInvAck = "RecvInvAck", sendGnt = "SendGnt", recvGnt = "RecvGnt"
    }

    package static var spec: TLASpec {
        #spec("APGermanData") { scope in
            let nodes = scope.parameter(as: Set<String>.self, in: Subsets(of: Set<String>(["n1_OF_NODE", "n2_OF_NODE"])))
            let noNode = scope.parameter(as: String.self, in: Set<String>(["noNode_OF_NODE"]))
            Assume(!nodes.contains(noNode))
            let data = scope.parameter(as: Set<String>.self, in: Subsets(of: Set<String>(["d1_OF_DATA", "d2_OF_DATA"])))
            let noData = scope.parameter(as: String.self, in: Set<String>(["noData_OF_DATA"]))
            Assume(!data.contains(noData))
            let payloads = data.inserting(noData)
            let requests = Set<String>(["ReqS", "ReqE"])
            let grants = Set<String>(["GntS", "GntE"])
            let cache = scope.sharedVar(initial: Dictionary<String, Line>.mapping(over: nodes) { _ in Line.expression(state: "I", data: noData) })
            let chan1 = scope.sharedVar(initial: Dictionary<String, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let chan2 = scope.sharedVar(initial: Dictionary<String, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let chan3 = scope.sharedVar(initial: Dictionary<String, Message>.mapping(over: nodes) { _ in Message.expression(cmd: "Empty", data: noData) })
            let invSet = scope.sharedVar(initial: Set<String>())
            let shrSet = scope.sharedVar(initial: Set<String>())
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

            Invariant("TypeOK") {
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
            Invariant("Coherence") {
                nodes.allSatisfy { i in nodes.allSatisfy { j in
                    i == j || ((cache[i].state != "E" || cache[j].state == "I") &&
                            (cache[i].state != "S" || cache[j].state == "I" || cache[j].state == "S"))
                } }
            }
            Invariant("DataProp") {
                exGntd || memData == auxData
                nodes.allSatisfy { i in cache[i].state == "I" || cache[i].data == auxData }
            }
            Invariant("TransactionConsistency") { (curCmd == "Empty") == (curPtr == noNode) }
            Invariant("DirectoryAccurate") {
                nodes.allSatisfy { i in (cache[i].state != "S" && cache[i].state != "E") || shrSet.contains(i) }
            }
            Invariant("ExclusiveIsolation") {
                nodes.allSatisfy { i in cache[i].state != "E" || (exGntd && nodes.allSatisfy { j in
                    i == j || (cache[j].state == "I" && !grants.contains(chan2[j].cmd) && chan3[j].cmd != "InvAck")
                }) }
            }
            Invariant("WritebackCarriesLatest") {
                nodes.allSatisfy { i in
                    chan3[i].cmd != "InvAck" || curCmd == "Empty" || !exGntd ||
                        (chan3[i].data == auxData && nodes.allSatisfy { j in
                            i == j || (cache[j].state != "E" && chan2[j].cmd != "GntE" && chan3[j].cmd != "InvAck")
                        })
                }
            }
            Validation("Upstream") {
                Bind(data, to: Set<String>(["d1_OF_DATA", "d2_OF_DATA"]))
                Bind(noData, to: "noData_OF_DATA")
                Bind(nodes, to: Set<String>(["n1_OF_NODE", "n2_OF_NODE"]))
                Bind(noNode, to: "noNode_OF_NODE")
            }
        }
    }
}

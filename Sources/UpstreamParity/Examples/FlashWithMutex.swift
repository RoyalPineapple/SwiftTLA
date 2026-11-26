// FLASH coordinates cache reads, exclusive writes and invalidations through a home directory.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/FlashProtocol/FlashWithMutex.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct FlashWithMutexModel: Sendable {
    package enum Symbol: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, d1, d2, undefined = "Undefined"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .undefined }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Text: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, d1, d2, undefined = "Undefined"
        case uniNone = "UNI_None", get = "UNI_Get", getX = "UNI_GetX"
        case put = "UNI_Put", putX = "UNI_PutX", nak = "UNI_Nak"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .undefined }
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package typealias Atom = OneOf<Symbol, Text>

    package struct Processor: Hashable, Sendable {
        package let ProcCmd: String
        package let InvMarked: Bool
        package let CacheState: String
        package let CacheData: Atom
    }

    package struct Directory: Hashable, Sendable {
        package let Pending: Bool
        package let Local: Bool
        package let Dirty: Bool
        package let HeadVld: Bool
        package let HeadPtr: Atom
        package let ShrVld: Bool
        package let ShrSet: Set<Atom>
        package let InvSet: Set<Atom>
    }

    package struct Message: Hashable, Sendable {
        package let Cmd: String
        package let Proc: Atom
        package let Data: Atom
    }

    package struct Signal: Hashable, Sendable {
        package let Cmd: String
    }

    private enum Step: String, CaseIterable {
        case store = "Store"
        case piRemote = "PI_Remote"
        case piRemoteReplace = "PI_Remote_Replace"
        case niLocalGetNak = "NI_Local_Get_Nak"
        case niLocalGetGet = "NI_Local_Get_Get"
        case niLocalGetPut = "NI_Local_Get_Put"
        case niLocalGetXNak = "NI_Local_GetX_Nak"
        case niLocalGetXGetX = "NI_Local_GetX_GetX"
        case niLocalGetXPutX = "NI_Local_GetX_PutX"
        case niInvAck = "NI_InvAck"
        case niReplace = "NI_Replace"
        case piRemotePutX = "PI_Remote_PutX"
        case niNak = "NI_Nak"
        case niRemotePut = "NI_Remote_Put"
        case niRemotePutX = "NI_Remote_PutX"
        case niInv = "NI_Inv"
        case niRemoteNak = "NI_Remote_Nak"
        case niRemoteGetPut = "NI_Remote_Get_Put"
        case niRemoteGetXPutX = "NI_Remote_GetX_PutX"
        case piLocalGetGet = "PI_Local_Get_Get"
        case piLocalGetPut = "PI_Local_Get_Put"
        case piLocalGetXGetX = "PI_Local_GetX_GetX"
        case piLocalGetXPutX = "PI_Local_GetX_PutX"
        case piLocalPutX = "PI_Local_PutX"
        case piLocalReplace = "PI_Local_Replace"
        case niNakClear = "NI_Nak_Clear"
        case niLocalPut = "NI_Local_Put"
        case niLocalPutXAcksDone = "NI_Local_PutXAcksDone"
        case niWb = "NI_Wb"
        case niFAck = "NI_FAck"
        case niShWb = "NI_ShWb"
    }

    package static var spec: TLASpec {
        #spec("FlashWithMutex") { scope in
            let nodes = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set<Atom>([Atom.first(Symbol.n1), Atom.first(Symbol.n2)]), Set<Atom>([Atom.second(Text.n1), Atom.second(Text.n2)])]))
            let data = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set<Atom>([Atom.first(Symbol.d1), Atom.first(Symbol.d2)]), Set<Atom>([Atom.second(Text.d1), Atom.second(Text.d2)])]))
            let absentSymbol: Atom = Atom.first(Symbol.undefined)
            let absentText: Atom = Atom.second(Text.undefined)
            let undefined = scope.parameter(as: Atom.self, in: Set<Atom>([absentSymbol, absentText]))
            Assume(!nodes.contains(undefined) && !data.contains(undefined))
            Assume(nodes.intersection(data).isEmpty && !nodes.isEmpty && !data.isEmpty)

            let Home = scope.sharedVar(initiallyIn: nodes)
            let Proc = scope.sharedVar(initial: Dictionary<Atom, Processor>.mapping(over: nodes) { _ in
                Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: "CACHE_I", CacheData: undefined)
            })
            let Dir = scope.sharedVar(initial: Directory.expression(
                Pending: false, Local: false, Dirty: false, HeadVld: false, HeadPtr: undefined,
                ShrVld: false, ShrSet: Set<Atom>(), InvSet: Set<Atom>()))
            let MemData = scope.sharedVar(initiallyIn: data)
            let UniMsg = scope.sharedVar(initial: Dictionary<Atom, Message>.mapping(over: nodes) { _ in
                Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined)
            })
            let InvMsg = scope.sharedVar(initial: Dictionary<Atom, Signal>.mapping(over: nodes) { _ in Signal.expression(Cmd: "INV_None") })
            let RpMsg = scope.sharedVar(initial: Dictionary<Atom, Signal>.mapping(over: nodes) { _ in Signal.expression(Cmd: "RP_None") })
            let WbMsg = scope.sharedVar(initial: Message.expression(Cmd: "WB_None", Proc: undefined, Data: undefined))
            let ShWbMsg = scope.sharedVar(initial: Message.expression(Cmd: "SHWB_None", Proc: undefined, Data: undefined))
            let NakcMsg = scope.sharedVar(initial: Signal.expression(Cmd: "NAKC_None"))
            let CurrData = scope.sharedVar(initial: MemData)
            let PrevData = scope.sharedVar(initial: MemData)
            let PendReqSrc = scope.sharedVar(initial: undefined)
            let PendReqCmd = scope.sharedVar(initial: undefined)
            let Collecting = scope.sharedVar(initial: false)
            let FwdCmd = scope.sharedVar(initial: "UNI_None")
            let FwdSrc = scope.sharedVar(initial: undefined)
            let requests = Set<String>(["Get", "GetX"])
            let unicastRequests = Set<String>(["UNI_Get", "UNI_GetX"])
            let invalidOrShared = Set<String>(["CACHE_I", "CACHE_S"])

            Do(Step.store, over: nodes, data) { src, value in
                When(Proc[src].CacheState == "CACHE_E")
                Proc[src].CacheData.set(value)
                CurrData.set(value)
            }

            Do(Step.piRemote, over: nodes, requests) { src, kind in
                When(src != Home && Proc[src].ProcCmd == "NODE_None" && Proc[src].CacheState == "CACHE_I")
                Proc[src].ProcCmd.set(If(kind == "Get", then: "NODE_Get", else: "NODE_GetX"))
                UniMsg[src].set(Message.expression(Cmd: If(kind == "Get", then: "UNI_Get", else: "UNI_GetX"), Proc: Home, Data: undefined))
            }

            Do(Step.piLocalGetGet) {
                When(Proc[Home].ProcCmd == "NODE_None" && Proc[Home].CacheState == "CACHE_I")
                When(!Dir.Pending && Dir.Dirty)
                Proc[Home].ProcCmd.set("NODE_Get")
                Dir.Pending.set(true)
                UniMsg[Home].set(Message.expression(Cmd: "UNI_Get", Proc: Dir.HeadPtr, Data: undefined))
                FwdCmd.set(If(Dir.HeadPtr != Home, then: "UNI_Get", else: FwdCmd))
                PendReqSrc.set(Home)
                PendReqCmd.set(Atom.second(Text.get))
                Collecting.set(false)
            }

            Do(Step.piLocalGetXGetX) {
                When(Proc[Home].ProcCmd == "NODE_None" && invalidOrShared.contains(Proc[Home].CacheState))
                When(!Dir.Pending && Dir.Dirty)
                Proc[Home].ProcCmd.set("NODE_GetX")
                Dir.Pending.set(true)
                UniMsg[Home].set(Message.expression(Cmd: "UNI_GetX", Proc: Dir.HeadPtr, Data: undefined))
                FwdCmd.set(If(Dir.HeadPtr != Home, then: "UNI_GetX", else: FwdCmd))
                PendReqSrc.set(Home)
                PendReqCmd.set(Atom.second(Text.getX))
                Collecting.set(false)
            }

            Do(Step.piLocalGetPut) {
                When(Proc[Home].ProcCmd == "NODE_None" && Proc[Home].CacheState == "CACHE_I")
                When(!Dir.Pending && !Dir.Dirty)
                Dir.Local.set(true)
                Proc[Home].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: If(Proc[Home].InvMarked, then: "CACHE_I", else: "CACHE_S"), CacheData: If(Proc[Home].InvMarked, then: undefined, else: MemData)))
            }

            Do(Step.piLocalGetXPutX) {
                When(Proc[Home].ProcCmd == "NODE_None" && invalidOrShared.contains(Proc[Home].CacheState))
                When(!Dir.Pending && !Dir.Dirty)
                Proc[Home].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: "CACHE_E", CacheData: MemData))
                If(Dir.HeadVld) {
                    let invalidate = nodes.filter { p in p != Home && ((Dir.ShrVld && Dir.ShrSet.contains(p)) || Dir.HeadPtr == p) }
                    InvMsg.set(Dictionary<Atom, Signal>.mapping(over: nodes) { p in Signal.expression(Cmd: If(invalidate.contains(p), then: "INV_Inv", else: "INV_None")) })
                    Dir.set(Directory.expression(Pending: true, Local: true, Dirty: true, HeadVld: false, HeadPtr: undefined, ShrVld: false, ShrSet: Set<Atom>(), InvSet: invalidate))
                    PendReqSrc.set(Home)
                    Collecting.set(true)
                    PrevData.set(CurrData)
                } else: {
                    Dir.Local.set(true)
                    Dir.Dirty.set(true)
                }
            }

            Do(Step.piRemotePutX, over: nodes) { dst in
                When(dst != Home && Proc[dst].ProcCmd == "NODE_None" && Proc[dst].CacheState == "CACHE_E")
                WbMsg.set(Message.expression(Cmd: "WB_Wb", Proc: dst, Data: Proc[dst].CacheData))
                Proc[dst].CacheState.set("CACHE_I")
                Proc[dst].CacheData.set(undefined)
            }

            Do(Step.piLocalPutX) {
                When(Proc[Home].ProcCmd == "NODE_None" && Proc[Home].CacheState == "CACHE_E")
                MemData.set(Proc[Home].CacheData)
                Proc[Home].CacheState.set("CACHE_I")
                Proc[Home].CacheData.set(undefined)
                Dir.Dirty.set(false)
                Dir.Local.set(Dir.Pending && Dir.Local)
            }

            Do(Step.piRemoteReplace, over: nodes) { src in
                When(src != Home && Proc[src].ProcCmd == "NODE_None" && Proc[src].CacheState == "CACHE_S")
                Proc[src].CacheState.set("CACHE_I")
                Proc[src].CacheData.set(undefined)
                RpMsg[src].Cmd.set("RP_Replace")
            }

            Do(Step.piLocalReplace) {
                When(Proc[Home].ProcCmd == "NODE_None" && Proc[Home].CacheState == "CACHE_S")
                Dir.Local.set(false)
                Proc[Home].CacheState.set("CACHE_I")
                Proc[Home].CacheData.set(undefined)
            }

            Do(Step.niNak, over: nodes) { dst in
                When(UniMsg[dst].Cmd == "UNI_Nak")
                UniMsg[dst].set(Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined))
                Proc[dst].ProcCmd.set("NODE_None")
                Proc[dst].InvMarked.set(false)
            }

            Do(Step.niNakClear) {
                When(NakcMsg.Cmd == "NAKC_Nakc")
                NakcMsg.Cmd.set("NAKC_None")
                Dir.Pending.set(false)
            }

            Do(Step.niLocalGetNak, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_Get" && UniMsg[src].Proc == Home)
                When(RpMsg[src].Cmd != "RP_Replace")
                When(Dir.Pending || (Dir.Dirty && Dir.Local && Proc[Home].CacheState != "CACHE_E") || (Dir.Dirty && !Dir.Local && Dir.HeadPtr == src))
                UniMsg[src].set(Message.expression(Cmd: "UNI_Nak", Proc: Home, Data: undefined))
            }

            Do(Step.niLocalGetGet, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_Get" && UniMsg[src].Proc == Home)
                When(RpMsg[src].Cmd != "RP_Replace")
                When(!Dir.Pending && Dir.Dirty && !Dir.Local && Dir.HeadPtr != src)
                Dir.Pending.set(true)
                UniMsg[src].set(Message.expression(Cmd: "UNI_Get", Proc: Dir.HeadPtr, Data: undefined))
                FwdCmd.set(If(Dir.HeadPtr != Home, then: "UNI_Get", else: FwdCmd))
                PendReqSrc.set(src)
                PendReqCmd.set(Atom.second(Text.get))
                Collecting.set(false)
            }

            Do(Step.niLocalGetXNak, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_GetX" && UniMsg[src].Proc == Home)
                When(Dir.Pending || (Dir.Dirty && Dir.Local && Proc[Home].CacheState != "CACHE_E") || (Dir.Dirty && !Dir.Local && Dir.HeadPtr == src))
                UniMsg[src].set(Message.expression(Cmd: "UNI_Nak", Proc: Home, Data: undefined))
            }

            Do(Step.niLocalGetXGetX, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_GetX" && UniMsg[src].Proc == Home)
                When(!Dir.Pending && Dir.Dirty && !Dir.Local && Dir.HeadPtr != src)
                Dir.Pending.set(true)
                UniMsg[src].set(Message.expression(Cmd: "UNI_GetX", Proc: Dir.HeadPtr, Data: undefined))
                FwdCmd.set(If(Dir.HeadPtr != Home, then: "UNI_GetX", else: FwdCmd))
                PendReqSrc.set(src)
                PendReqCmd.set(Atom.second(Text.getX))
                Collecting.set(false)
            }


            Do(Step.niLocalGetPut, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_Get" && UniMsg[src].Proc == Home)
                When(RpMsg[src].Cmd != "RP_Replace" && !Dir.Pending)
                When(!Dir.Dirty || (Dir.Local && Proc[Home].CacheState == "CACHE_E"))
                If(Dir.Dirty) {
                    MemData.set(Proc[Home].CacheData)
                    Proc[Home].CacheState.set("CACHE_S")
                    UniMsg[src].set(Message.expression(Cmd: "UNI_Put", Proc: Home, Data: Proc[Home].CacheData))
                    Dir.Dirty.set(false)
                    Dir.HeadVld.set(true)
                    Dir.HeadPtr.set(src)
                } else: {
                    UniMsg[src].set(Message.expression(Cmd: "UNI_Put", Proc: Home, Data: MemData))
                    If(Dir.HeadVld) {
                        Dir.ShrVld.set(true)
                        Dir.InvSet.set(Dir.ShrSet.inserting(src))
                        Dir.ShrSet.insert(src)
                    } else: {
                        Dir.HeadVld.set(true)
                        Dir.HeadPtr.set(src)
                    }
                }
            }

            Do(Step.niRemoteNak, over: nodes, nodes) { src, dst in
                When(src != dst && dst != Home && unicastRequests.contains(UniMsg[src].Cmd))
                When(UniMsg[src].Proc == dst && Proc[dst].CacheState != "CACHE_E")
                UniMsg[src].set(Message.expression(Cmd: "UNI_Nak", Proc: dst, Data: undefined))
                NakcMsg.Cmd.set("NAKC_Nakc")
                FwdCmd.set("UNI_None")
                FwdSrc.set(src)
            }

            Do(Step.niRemoteGetPut, over: nodes, nodes) { src, dst in
                When(src != dst && dst != Home && UniMsg[src].Cmd == "UNI_Get")
                When(UniMsg[src].Proc == dst && Proc[dst].CacheState == "CACHE_E")
                UniMsg[src].set(Message.expression(Cmd: "UNI_Put", Proc: dst, Data: Proc[dst].CacheData))
                If(src != Home) {
                    ShWbMsg.set(Message.expression(Cmd: "SHWB_ShWb", Proc: src, Data: Proc[dst].CacheData))
                }
                Proc[dst].CacheState.set("CACHE_S")
                FwdCmd.set("UNI_None")
                FwdSrc.set(src)
            }

            Do(Step.niRemoteGetXPutX, over: nodes, nodes) { src, dst in
                When(src != dst && dst != Home && UniMsg[src].Cmd == "UNI_GetX")
                When(UniMsg[src].Proc == dst && Proc[dst].CacheState == "CACHE_E")
                UniMsg[src].set(Message.expression(Cmd: "UNI_PutX", Proc: dst, Data: Proc[dst].CacheData))
                If(src != Home) {
                    ShWbMsg.set(Message.expression(Cmd: "SHWB_FAck", Proc: src, Data: undefined))
                }
                Proc[dst].CacheState.set("CACHE_I")
                Proc[dst].CacheData.set(undefined)
                FwdCmd.set("UNI_None")
                FwdSrc.set(src)
            }

            Do(Step.niLocalGetXPutX, over: nodes) { src in
                When(src != Home && UniMsg[src].Cmd == "UNI_GetX" && UniMsg[src].Proc == Home)
                When(!Dir.Pending && (!Dir.Dirty || (Dir.Local && Proc[Home].CacheState == "CACHE_E")))
                If(Dir.Dirty) {
                    UniMsg[src].set(Message.expression(Cmd: "UNI_PutX", Proc: Home, Data: Proc[Home].CacheData))
                    Proc[Home].CacheState.set("CACHE_I")
                    Proc[Home].CacheData.set(undefined)
                } else: {
                    UniMsg[src].set(Message.expression(Cmd: "UNI_PutX", Proc: Home, Data: MemData))
                    let noOtherSharers = !Dir.HeadVld || (Dir.HeadPtr == src && Dir.ShrSet.removing(src).isEmpty)
                    If(Dir.Local || noOtherSharers) {
                        Proc[Home].CacheState.set("CACHE_I")
                        Proc[Home].CacheData.set(undefined)
                    }
                    If(Dir.Local && Proc[Home].ProcCmd == "NODE_Get") {
                        Proc[Home].InvMarked.set(true)
                    }
                    If(!noOtherSharers) {
                        let invalidate = nodes.filter { p in p != Home && p != src && ((Dir.ShrVld && Dir.ShrSet.contains(p)) || (Dir.HeadVld && Dir.HeadPtr == p)) }
                        InvMsg.set(Dictionary<Atom, Signal>.mapping(over: nodes) { p in Signal.expression(Cmd: If(invalidate.contains(p), then: "INV_Inv", else: "INV_None")) })
                        Dir.InvSet.set(invalidate)
                        Dir.Pending.set(true)
                        PendReqSrc.set(src)
                        PendReqCmd.set(Atom.second(Text.getX))
                        Collecting.set(true)
                        PrevData.set(CurrData)
                    } else: {
                        Dir.InvSet.set(Set<Atom>())
                    }
                }
                If(Dir.Dirty) {
                    Dir.InvSet.set(Set<Atom>())
                }
                Dir.Local.set(false)
                Dir.Dirty.set(true)
                Dir.HeadVld.set(true)
                Dir.HeadPtr.set(src)
                Dir.ShrVld.set(false)
                Dir.ShrSet.set(Set<Atom>())
            }

            Do(Step.niLocalPut) {
                When(UniMsg[Home].Cmd == "UNI_Put")
                Proc[Home].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: If(Proc[Home].InvMarked, then: "CACHE_I", else: "CACHE_S"), CacheData: If(Proc[Home].InvMarked, then: undefined, else: UniMsg[Home].Data)))
                Dir.Dirty.set(false)
                MemData.set(UniMsg[Home].Data)
                Dir.Pending.set(false)
                Dir.Local.set(true)
                UniMsg[Home].set(Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niRemotePut, over: nodes) { dst in
                When(dst != Home)
                When(UniMsg[dst].Cmd == "UNI_Put")
                Proc[dst].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: If(Proc[dst].InvMarked, then: "CACHE_I", else: "CACHE_S"), CacheData: If(Proc[dst].InvMarked, then: undefined, else: UniMsg[dst].Data)))
                UniMsg[dst].set(Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niLocalPutXAcksDone) {
                When(UniMsg[Home].Cmd == "UNI_PutX")
                Proc[Home].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: "CACHE_E", CacheData: UniMsg[Home].Data))
                Dir.HeadVld.set(false)
                Dir.HeadPtr.set(undefined)
                Dir.Pending.set(false)
                Dir.Local.set(true)
                UniMsg[Home].set(Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niRemotePutX, over: nodes) { dst in
                When(dst != Home)
                When(UniMsg[dst].Cmd == "UNI_PutX")
                When(Proc[dst].ProcCmd == "NODE_GetX")
                Proc[dst].set(Processor.expression(ProcCmd: "NODE_None", InvMarked: false, CacheState: "CACHE_E", CacheData: UniMsg[dst].Data))
                UniMsg[dst].set(Message.expression(Cmd: "UNI_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niInv, over: nodes) { dst in
                When(dst != Home && InvMsg[dst].Cmd == "INV_Inv")
                InvMsg[dst].Cmd.set("INV_InvAck")
                Proc[dst].CacheState.set("CACHE_I")
                Proc[dst].CacheData.set(undefined)
                Proc[dst].InvMarked.set(Proc[dst].ProcCmd == "NODE_Get" || Proc[dst].InvMarked)
            }

            Do(Step.niInvAck, over: nodes) { src in
                When(src != Home && InvMsg[src].Cmd == "INV_InvAck")
                When(Dir.Pending && Dir.InvSet.contains(src))
                If(Dir.InvSet.removing(src).isEmpty) {
                    Dir.Pending.set(false)
                    Dir.Local.set(Dir.Local && Dir.Dirty)
                    Collecting.set(false)
                }
                Dir.InvSet.remove(src)
                InvMsg[src].Cmd.set("INV_None")
            }

            Do(Step.niWb) {
                When(WbMsg.Cmd == "WB_Wb")
                MemData.set(WbMsg.Data)
                WbMsg.set(Message.expression(Cmd: "WB_None", Proc: undefined, Data: undefined))
                Dir.Dirty.set(false)
                Dir.HeadVld.set(false)
                Dir.HeadPtr.set(undefined)
            }

            Do(Step.niFAck) {
                When(ShWbMsg.Cmd == "SHWB_FAck")
                Dir.Pending.set(false)
                Dir.HeadPtr.set(If(Dir.Dirty, then: ShWbMsg.Proc, else: Dir.HeadPtr))
                ShWbMsg.set(Message.expression(Cmd: "SHWB_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niShWb) {
                When(ShWbMsg.Cmd == "SHWB_ShWb")
                Dir.Pending.set(false)
                Dir.Dirty.set(false)
                Dir.ShrVld.set(true)
                Dir.InvSet.set(Dir.ShrSet.inserting(ShWbMsg.Proc))
                Dir.ShrSet.insert(ShWbMsg.Proc)
                MemData.set(ShWbMsg.Data)
                ShWbMsg.set(Message.expression(Cmd: "SHWB_None", Proc: undefined, Data: undefined))
            }

            Do(Step.niReplace, over: nodes) { src in
                When(RpMsg[src].Cmd == "RP_Replace")
                RpMsg[src].Cmd.set("RP_None")
                If(Dir.ShrVld) {
                    Dir.ShrSet.remove(src)
                    Dir.InvSet.remove(src)
                }
            }


            let nodeOrUndefined = nodes.inserting(undefined)
            let dataOrUndefined = data.inserting(undefined)
            let unicastCommands = Set<String>(["UNI_None", "UNI_Get", "UNI_GetX", "UNI_Put", "UNI_PutX", "UNI_Nak"])
            Invariant("TypeOK") {
                nodes.contains(Home) && Proc.keys == nodes
                nodes.allSatisfy { n in
                    Set<String>(["NODE_None", "NODE_Get", "NODE_GetX"]).contains(Proc[n].ProcCmd)
                        && Set<String>(["CACHE_I", "CACHE_S", "CACHE_E"]).contains(Proc[n].CacheState)
                        && dataOrUndefined.contains(Proc[n].CacheData)
                }
                nodeOrUndefined.contains(Dir.HeadPtr) && Dir.ShrSet.isSubset(of: nodes) && Dir.InvSet.isSubset(of: nodes)
                data.contains(MemData) && data.contains(CurrData) && data.contains(PrevData)
                UniMsg.keys == nodes && InvMsg.keys == nodes && RpMsg.keys == nodes
                nodes.allSatisfy { n in
                    unicastCommands.contains(UniMsg[n].Cmd) && nodeOrUndefined.contains(UniMsg[n].Proc)
                        && dataOrUndefined.contains(UniMsg[n].Data)
                        && Set<String>(["INV_None", "INV_Inv", "INV_InvAck"]).contains(InvMsg[n].Cmd)
                        && Set<String>(["RP_None", "RP_Replace"]).contains(RpMsg[n].Cmd)
                }
                Set<String>(["WB_None", "WB_Wb"]).contains(WbMsg.Cmd)
                    && nodeOrUndefined.contains(WbMsg.Proc) && dataOrUndefined.contains(WbMsg.Data)
                Set<String>(["SHWB_None", "SHWB_ShWb", "SHWB_FAck"]).contains(ShWbMsg.Cmd)
                    && nodeOrUndefined.contains(ShWbMsg.Proc) && dataOrUndefined.contains(ShWbMsg.Data)
                Set<String>(["NAKC_None", "NAKC_Nakc"]).contains(NakcMsg.Cmd)
                nodeOrUndefined.contains(PendReqSrc) && nodeOrUndefined.contains(FwdSrc)
                Set<Atom>([Atom.second(Text.uniNone), Atom.second(Text.get), Atom.second(Text.getX), Atom.second(Text.put), Atom.second(Text.putX), Atom.second(Text.nak)]).inserting(undefined).contains(PendReqCmd)
                    && unicastCommands.contains(FwdCmd)
            }
            Invariant("CacheStateProp") {
                nodes.allSatisfy { p in nodes.allSatisfy { q in
                    p == q || Proc[p].CacheState != "CACHE_E" || Proc[q].CacheState != "CACHE_E"
                } }
            }
            Invariant("CacheDataProp") {
                nodes.allSatisfy { p in
                    (Proc[p].CacheState != "CACHE_E" || Proc[p].CacheData == CurrData)
                        && (Proc[p].CacheState != "CACHE_S" || Proc[p].CacheData == If(Collecting, then: PrevData, else: CurrData))
                }
            }
            Invariant("MemDataProp") { Dir.Dirty || MemData == CurrData }
            Invariant("Lemma_1") {
                nodes.allSatisfy { dst in Proc[dst].CacheState != "CACHE_E" ||
                    (Dir.Dirty && WbMsg.Cmd != "WB_Wb" && ShWbMsg.Cmd != "SHWB_ShWb" && UniMsg[Home].Cmd != "UNI_Put"
                        && nodes.allSatisfy { p in p == dst || Proc[p].CacheState != "CACHE_E" }
                        && nodes.allSatisfy { q in UniMsg[q].Cmd != "UNI_PutX" })
                }
            }
            Invariant("Lemma_2") {
                nodes.allSatisfy { src in nodes.allSatisfy { dst in
                    src == dst || dst == Home || UniMsg[src].Cmd != "UNI_Get" || UniMsg[src].Proc != dst
                        || (Dir.Pending && !Dir.Local && PendReqSrc == src && FwdCmd == "UNI_Get")
                } }
            }
            Invariant("Lemma_3") {
                nodes.allSatisfy { src in nodes.allSatisfy { dst in
                    src == dst || dst == Home || UniMsg[src].Cmd != "UNI_GetX" || UniMsg[src].Proc != dst
                        || (Dir.Pending && !Dir.Local && PendReqSrc == src && FwdCmd == "UNI_GetX")
                } }
            }
            Invariant("Lemma_4") {
                nodes.allSatisfy { p in p == Home || InvMsg[p].Cmd != "INV_InvAck" ||
                    (Dir.Pending && Collecting && NakcMsg.Cmd == "NAKC_None" && ShWbMsg.Cmd == "SHWB_None"
                        && nodes.allSatisfy { q in
                            (!unicastRequests.contains(UniMsg[q].Cmd) || UniMsg[q].Proc == Home)
                                && (UniMsg[q].Cmd != "UNI_PutX" || (UniMsg[q].Proc == Home && PendReqSrc == q))
                        })
                }
            }
            Invariant("Lemma_5") {
                nodes.allSatisfy { p in Proc[p].CacheState != "CACHE_E" || Proc[p].CacheData == CurrData }
            }

            Validation("APFlashWithMutex") {
                Bind(nodes, to: Set<Atom>([Atom.second(Text.n1), Atom.second(Text.n2)]))
                Bind(data, to: Set<Atom>([Atom.second(Text.d1), Atom.second(Text.d2)]))
                Bind(undefined, to: absentText)
            }
            let cacheSymmetry = Symmetry(independently: nodes, data)
            Validation("MCFlashWithMutex") {
                Bind(nodes, to: Set<Atom>([Atom.first(Symbol.n1), Atom.first(Symbol.n2)]))
                Bind(data, to: Set<Atom>([Atom.first(Symbol.d1), Atom.first(Symbol.d2)]))
                Bind(undefined, to: absentSymbol)
            }.usingSymmetry(cacheSymmetry)
        }
    }
}

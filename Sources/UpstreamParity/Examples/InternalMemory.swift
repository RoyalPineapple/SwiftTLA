// The memory handles a request, performs the operation, and returns a response.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/CachingMemory/InternalMemory.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct InternalMemoryModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case p1, p2, a1, a2, a3, v1, v2, noVal = "NoVal"
        package static var defaultValue: Self { .p1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct Read: Hashable, Sendable {
        package let op: String
        package let adr: Atom
    }
    package struct Write: Hashable, Sendable {
        package let op: String
        package let adr: Atom
        package let val: Atom
    }
    package typealias Request = OneOf<Read, Write>
    package typealias Message = OneOf<Request, Atom>
    private enum Step: String, CaseIterable {
        case acceptRequest = "Req"
        case serviceRequest = "Do"
        case sendReply = "Rsp"
    }

    package static var spec: TLASpec {
        #spec("MCInternalMemory") { scope in
            let processes = scope.parameter(tlaName: "Proc", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.p1, Atom.p2])))
            let addresses = scope.parameter(tlaName: "Adr", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.a1, Atom.a2, Atom.a3])))
            let values = scope.parameter(tlaName: "Val", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.v1, Atom.v2])))
            let noValue = scope.parameter(tlaName: "NoVal_1", as: Atom.self, in: Set<Atom>([Atom.noVal]))
            let reads = addresses.mapping { a in Request.first(Read.expression(op: "Rd", adr: a)) }
            let writes = addresses.flatMapping { a in values.mapping { v in Request.second(Write.expression(op: "Wr", adr: a, val: v)) } }
            let writeMessages = writes.mapping { r in Message.first(r) }
            let requestMessages = reads.union(writes).mapping { r in Message.first(r) }
            let replyValues = values.inserting(noValue).mapping { v in Message.second(v) }
            let memory = scope.sharedVar(tlaName: "mem", initiallyIn: Functions(from: addresses, to: values))
            let requestPhase = scope.sharedVar(tlaName: "ctl", initial: Dictionary<Atom, String>.mapping(over: processes) { _ in "rdy" })
            let messageBuffer = scope.sharedVar(tlaName: "buf", initial: Dictionary<Atom, Message>.mapping(over: processes) { _ in Message.second(noValue) })
            let firstProcess = Select(from: processes) { _ in true }
            let memoryInterface = scope.sharedVar(tlaName: "memInt", initial: Pair<Atom, Message>.literal(firstProcess, Message.second(noValue)))

            Do(Step.acceptRequest, over: processes) { p in
                When(requestPhase[p] == "rdy")
                With(requestMessages) { request in
                    memoryInterface.set(Pair<Atom, Message>.literal(p, request))
                    messageBuffer[p].set(request)
                    requestPhase[p].set("busy")
                }
            }
            let serviceRequest = Do(Step.serviceRequest, over: processes) { p in
                When(requestPhase[p] == "busy")
                let isWrite = writeMessages.contains(messageBuffer[p])
                let reply = If(isWrite, then: Message.second(noValue),
                    else: Message.second(memory[messageBuffer[p].assuming(Read.self).adr]))
                memory.set(If(isWrite,
                    then: memory.updating(messageBuffer[p].assuming(Write.self).adr, to: messageBuffer[p].assuming(Write.self).val),
                    else: memory))
                messageBuffer[p].set(reply)
                requestPhase[p].set("done")
            }
            let sendReply = Do(Step.sendReply, over: processes) { p in
                When(requestPhase[p] == "done")
                memoryInterface.set(Pair<Atom, Message>.literal(p, messageBuffer[p]))
                requestPhase[p].set("rdy")
            }
            WeakFairness(eachOf: [serviceRequest, sendReply])
            let typeInvariant = Invariant("TypeInvariant")
            typeInvariant {
                memory.keys == addresses && addresses.allSatisfy { a in values.contains(memory[a]) }
                    && requestPhase.keys == processes && messageBuffer.keys == processes
                    && processes.allSatisfy { p in Set<String>(["rdy","busy","done"]).contains(requestPhase[p])
                        && requestMessages.union(replyValues).contains(messageBuffer[p])
                    }
            }
            let LivenessProperty = Temporal()
            LivenessProperty(forEach: processes) { p in .leadsTo(requestPhase[p] == "busy", requestPhase[p] == "rdy") }
            let Liveness = Temporal()
            Liveness(forEach: processes) { p in .all([
                .leadsTo(requestPhase[p] == "busy", requestPhase[p] != "busy"),
                .leadsTo(requestPhase[p] == "done", requestPhase[p] != "done")
            ]) }
            // ISpec has no fairness clauses. LISpec adds one grouped obligation per processor.
            let ISpec = FairnessProfile(excluding: [Step.serviceRequest, Step.sendReply])
            Validation("Upstream") {
                Bind(processes, to: Set<Atom>([Atom.p1, Atom.p2]))
                Bind(addresses, to: Set<Atom>([Atom.a1, Atom.a2, Atom.a3]))
                Bind(values, to: Set<Atom>([Atom.v1, Atom.v2]))
                Bind(noValue, to: Atom.noVal)
            }.usingFairness(ISpec).checking(only: [typeInvariant])
            Validation("Live") {
                Bind(processes, to: Set<Atom>([Atom.p1, Atom.p2]))
                Bind(addresses, to: Set<Atom>([Atom.a1, Atom.a2, Atom.a3]))
                Bind(values, to: Set<Atom>([Atom.v1, Atom.v2]))
                Bind(noValue, to: Atom.noVal)
            }.checking(only: [LivenessProperty, Liveness])
        }
    }
}

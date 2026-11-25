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
    private enum Step: String, CaseIterable { case request = "Req", perform = "Do", respond = "Rsp" }

    package static var spec: TLASpec {
        #spec("MCInternalMemory") { scope in
            let Proc = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.p1, Atom.p2])))
            let Adr = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.a1, Atom.a2, Atom.a3])))
            let Val = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.v1, Atom.v2])))
            let NoVal = scope.parameter(as: Atom.self, in: Set<Atom>([Atom.noVal]))
            let reads = Adr.mapping { a in Request.first(Read.expression(op: "Rd", adr: a)) }
            let writes = Adr.flatMapping { a in Val.mapping { v in Request.second(Write.expression(op: "Wr", adr: a, val: v)) } }
            let writeMessages = writes.mapping { r in Message.first(r) }
            let requestMessages = reads.union(writes).mapping { r in Message.first(r) }
            let replyValues = Val.inserting(NoVal).mapping { v in Message.second(v) }
            let mem = scope.sharedVar(initiallyIn: Functions(from: Adr, to: Val))
            let ctl = scope.sharedVar(initial: Dictionary<Atom, String>.mapping(over: Proc) { _ in "rdy" })
            let buf = scope.sharedVar(initial: Dictionary<Atom, Message>.mapping(over: Proc) { _ in Message.second(NoVal) })
            let firstProcess = Select(from: Proc) { _ in true }
            let memInt = scope.sharedVar(initial: Pair<Atom, Message>.literal(firstProcess, Message.second(NoVal)))

            Do(Step.request, over: Proc) { p in
                When(ctl[p] == "rdy")
                With(requestMessages) { request in
                    memInt.set(Pair<Atom, Message>.literal(p, request))
                    buf[p].set(request)
                    ctl[p].set("busy")
                }
            }
            Do(Step.perform, over: Proc) { p in
                When(ctl[p] == "busy")
                let isWrite = writeMessages.contains(buf[p])
                let reply = If(isWrite, then: Message.second(NoVal),
                    else: Message.second(mem[buf[p].assuming(Read.self).adr]))
                mem.set(If(isWrite,
                    then: mem.updating(buf[p].assuming(Write.self).adr, to: buf[p].assuming(Write.self).val),
                    else: mem))
                buf[p].set(reply)
                ctl[p].set("done")
            }
            Do(Step.respond, over: Proc) { p in
                When(ctl[p] == "done")
                memInt.set(Pair<Atom, Message>.literal(p, buf[p]))
                ctl[p].set("rdy")
            }
            Invariant("TypeInvariant") {
                mem.keys == Adr && Adr.allSatisfy { a in Val.contains(mem[a]) }
                    && ctl.keys == Proc && buf.keys == Proc
                    && Proc.allSatisfy { p in Set<String>(["rdy","busy","done"]).contains(ctl[p])
                        && requestMessages.union(replyValues).contains(buf[p])
                    }
            }
            Validation("Upstream") {
                Bind(Proc, to: Set<Atom>([Atom.p1, Atom.p2]))
                Bind(Adr, to: Set<Atom>([Atom.a1, Atom.a2, Atom.a3]))
                Bind(Val, to: Set<Atom>([Atom.v1, Atom.v2]))
                Bind(NoVal, to: Atom.noVal)
            }
        }
    }
}

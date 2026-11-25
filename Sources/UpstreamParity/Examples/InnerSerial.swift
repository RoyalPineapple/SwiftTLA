import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct InnerSerialModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case p1, p2, r1, a1, v1, v2, done = "Done", initWr = "InitWr"
        package static var defaultValue: Self { .p1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct RegisterValue: Hashable, Sendable {
        package let adr: Atom
        package let val: Atom
        package let op: String
    }
    package struct Operation: Hashable, Sendable {
        package let req: RegisterValue
        package let reg: Atom
    }
    package struct OperationID: Hashable, Sendable {
        package let proc: Atom
        package let idx: Int
    }
    package typealias Origin = OneOf<OperationID, Atom>
    package struct ResponseSubject: Hashable, Sendable {
        package let proc: Atom
        package let reg: Atom
        package let idx: Int
    }
    package struct ReadOperation: Hashable, Sendable {
        package let req: RegisterValue
        package let reg: Atom
        package let source: Origin
    }
    package typealias QueueEntry = OneOf<Operation, ReadOperation>
    private enum Step: String, CaseIterable { case issue = "IssueRequest", write = "RespondToWr", read = "RespondToRd", internalOrder = "Internal" }
    package static var spec: TLASpec {
        #spec("MCInnerSerial") { scope in
            Extends(.naturals, .sequences, .finiteSets)
            let Proc = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.p1, Atom.p2])))
            let Reg = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.r1])))
            let Adr = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.a1])))
            let Val = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.v1, Atom.v2])))
            let InitWr = scope.parameter(as: Atom.self, in: Set<Atom>([Atom.initWr]))
            let MaxQLen = scope.parameter(as: Int.self, in: 1...1)
            let free = Adr.flatMapping { a in Val.mapping { v in RegisterValue.expression(adr: a, val: v, op: "Free") } }
            let requests = Adr.flatMapping { a in Val.flatMapping { v in
                Set<String>(["Rd", "Wr"]).mapping { op in RegisterValue.expression(adr: a, val: v, op: op) }
            } }
            let regFile = scope.sharedVar(initiallyIn: Functions(from: Proc, to: Functions(from: Reg, to: free)))
            let opQ = scope.sharedVar(initial: Dictionary<Atom, [QueueEntry]>.mapping(over: Proc) { _ in [QueueEntry]() })
            let opOrder = scope.sharedVar(initial: Set<TupleExpr<OperationID>>())
            let updateOpOrder = Macro {
                let ids = Proc.flatMapping { p in
                    IntRange(1, through: opQ[p].count).mapping { i in OperationID.expression(proc: p, idx: i) }
                }
                let edges = ids.flatMapping { i in ids.mapping { j in TupleExpr<OperationID>.literal(i, j) } }
                let requestsAfter = Dictionary<OperationID, RegisterValue>.mapping(over: ids) { i in
                    If(opQ[i.proc][i.idx].recordFields.contains("source"),
                        then: opQ[i.proc][i.idx].assuming(ReadOperation.self).req,
                        else: opQ[i.proc][i.idx].assuming(Operation.self).req)
                }
                With(Subsets(of: edges)) { total in
                    When(ids.allSatisfy { i in !total.contains(TupleExpr<OperationID>.literal(i, i)) })
                    When(ids.allSatisfy { i in ids.allSatisfy { j in
                        i == j || total.contains(TupleExpr<OperationID>.literal(i, j))
                            || total.contains(TupleExpr<OperationID>.literal(j, i))
                    } })
                    When(ids.allSatisfy { i in ids.allSatisfy { j in ids.allSatisfy { k in
                        !total.contains(TupleExpr<OperationID>.literal(i, j))
                            || !total.contains(TupleExpr<OperationID>.literal(j, k))
                            || total.contains(TupleExpr<OperationID>.literal(i, k))
                    } } })
                    When(ids.allSatisfy { i in ids.allSatisfy { j in
                        i.proc != j.proc || i.idx >= j.idx || total.contains(TupleExpr<OperationID>.literal(i, j))
                    } })
                    let reads = ids.filter { i in opQ[i.proc][i.idx].recordFields.contains("source") }
                    When(reads.allSatisfy { i in
                        !ids.contains { j in
                            requestsAfter[j].op == "Wr" && requestsAfter[j].adr == requestsAfter[i].adr
                                && total.contains(TupleExpr<OperationID>.literal(j, i))
                                && (opQ[i.proc][i.idx].assuming(ReadOperation.self).source == Origin.second(InitWr)
                                    || ids.contains { sourceID in
                                        sourceID.proc == opQ[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).proc
                                            && sourceID.idx == opQ[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).idx
                                            && total.contains(TupleExpr<OperationID>.literal(sourceID, j))
                                    })
                        }
                    })
                    When(opOrder.isSubset(of: total))
                    With(Subsets(of: total)) { candidate in
                        When(opOrder.isSubset(of: candidate))
                        opOrder.set(candidate)
                    }
                }
            }
            let operationIDs = Proc.flatMapping { p in
                IntRange(1, through: opQ[p].count).mapping { idx in OperationID.expression(proc: p, idx: idx) }
            }
            let requestAt = Dictionary<OperationID, RegisterValue>.mapping(over: operationIDs) { i in
                If(opQ[i.proc][i.idx].recordFields.contains("source"),
                    then: opQ[i.proc][i.idx].assuming(ReadOperation.self).req,
                    else: opQ[i.proc][i.idx].assuming(Operation.self).req)
            }
            let registerAt = Dictionary<OperationID, Atom>.mapping(over: operationIDs) { i in
                If(opQ[i.proc][i.idx].recordFields.contains("source"),
                    then: opQ[i.proc][i.idx].assuming(ReadOperation.self).reg,
                    else: opQ[i.proc][i.idx].assuming(Operation.self).reg)
            }
            let initialValue = Select(from: Val) { _ in true }
            Do(Step.issue, over: Proc, requests, Reg) { proc, req, reg in
                When(regFile[proc][reg].op == "Free")
                let queued = opQ[proc].appending(QueueEntry.first(Operation.expression(req: req, reg: reg)))
                regFile[proc][reg].set(req)
                opQ[proc].set(queued)
                updateOpOrder()
            }
            let write = Do(Step.write, over: Proc, Reg) { proc, reg in
                When(regFile[proc][reg].op == "Wr")
                let idx = Select(from: IntRange(1, through: opQ[proc].count)) { i in
                    registerAt[OperationID.expression(proc: proc, idx: i)] == reg
                }
                let id = OperationID.expression(proc: proc, idx: idx)
                let done = QueueEntry.first(Operation.expression(req: RegisterValue.expression(adr: requestAt[id].adr, val: requestAt[id].val, op: requestAt[id].op), reg: Atom.done))
                let queue = SequenceMapping(length: opQ[proc].count) { i in If(i == idx, then: done, else: opQ[proc][i]) }
                regFile[proc][reg].op.set("Free")
                opQ[proc].set(queue)
                updateOpOrder()
            }
            write
            let read = Do(Step.read, over: Proc, Reg) { proc, reg in
                let req = regFile[proc][reg]
                When(req.op == "Rd")
                let idx = Select(from: IntRange(1, through: opQ[proc].count)) { i in
                    registerAt[OperationID.expression(proc: proc, idx: i)] == reg
                }
                let writes = operationIDs.filter { w in requestAt[w].op == "Wr" && requestAt[w].adr == req.adr }
                let sources = writes.mapping { w in Origin.first(w) }.inserting(Origin.second(InitWr))
                With(sources) { src in
                    let val = If(src == Origin.second(InitWr), then: initialValue,
                        else: requestAt[Select(from: writes) { w in w.proc == src.assuming(OperationID.self).proc && w.idx == src.assuming(OperationID.self).idx }].val)
                    let reply = RegisterValue.expression(adr: req.adr, val: val, op: "Rd")
                    let done = QueueEntry.second(ReadOperation.expression(req: reply, reg: Atom.done, source: src))
                    let queue = SequenceMapping(length: opQ[proc].count) { i in If(i == idx, then: done, else: opQ[proc][i]) }
                    regFile[proc][reg].val.set(val)
                    regFile[proc][reg].op.set("Free")
                    opQ[proc].set(queue)
                    updateOpOrder()
                }
            }
            read
            let orderStep = Do(Step.internalOrder) { updateOpOrder() }
            orderStep
            // With two processes and one queue entry each, a nonstuttering Internal step
            // orders their two live IDs. Every other distinct-ID pair is disabled.
            WeakFairness(orderStep)
            WeakFairness(eachOf: [read, write])
            let registerValues = free.union(requests)
            let completedReads = operationIDs.filter { i in opQ[i.proc][i.idx].recordFields.contains("source") }
            Invariant("DataInvariant") {
                regFile.keys == Proc && opQ.keys == Proc
                    && Proc.allSatisfy { p in regFile[p].keys == Reg
                        && Reg.allSatisfy { r in registerValues.contains(regFile[p][r])
                            && operationIDs.filter { i in i.proc == p && registerAt[i] == r }.count
                                == If(regFile[p][r].op == "Free", then: 0, else: 1)
                        }
                    }
                    && opOrder.allSatisfy { edge in
                        edge.count == 2 && operationIDs.contains(edge[1]) && operationIDs.contains(edge[2])
                    }
                    && operationIDs.allSatisfy { i in
                        Adr.contains(requestAt[i].adr) && Val.contains(requestAt[i].val)
                            && Set<String>(["Rd", "Wr"]).contains(requestAt[i].op)
                            && If(registerAt[i] == Atom.done,
                                then: If(completedReads.contains(i), then: requestAt[i].op == "Rd", else: requestAt[i].op == "Wr"),
                                else: Reg.contains(registerAt[i]) && !completedReads.contains(i)
                                    && regFile[i.proc][registerAt[i]].adr == requestAt[i].adr
                                    && regFile[i.proc][registerAt[i]].op == requestAt[i].op
                                    && regFile[i.proc][registerAt[i]].val == requestAt[i].val)
                    }
                    && completedReads.allSatisfy { i in
                        If(opQ[i.proc][i.idx].assuming(ReadOperation.self).source == Origin.second(InitWr),
                            then: requestAt[i].val == initialValue,
                            else: operationIDs.contains { w in
                                w.proc == opQ[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).proc
                                    && w.idx == opQ[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).idx
                                    && requestAt[w].op == "Wr" && requestAt[w].adr == requestAt[i].adr
                                    && requestAt[w].val == requestAt[i].val
                            })
                    }
            }
            Constraint(Proc.allSatisfy { p in opQ[p].count <= MaxQLen })
            // Index -1 identifies a register obligation. MCNat starts at zero.
            let slots = Proc.flatMapping { p in Reg.mapping { r in ResponseSubject.expression(proc: p, reg: r, idx: -1) } }
            let subjects = slots.union(Proc.flatMapping { p in
                IntRange(0, through: MaxQLen).mapping { i in ResponseSubject.expression(proc: p, reg: p, idx: i) }
            })
            let completedIDs = operationIDs.filter { i in registerAt[i] == Atom.done }
            let AlwaysResponds = Temporal()
            AlwaysResponds(forEach: subjects) { s in
                .conditional(s.idx == -1,
                    then: .leadsTo(regFile[s.proc][s.reg].op != "Free", regFile[s.proc][s.reg].op == "Free"),
                    else: .leadsTo(operationIDs.contains(OperationID.expression(proc: s.proc, idx: s.idx)),
                        completedIDs.contains(OperationID.expression(proc: s.proc, idx: s.idx))))
            }
            Validation("Upstream") {
                Bind(Proc, to: Set<Atom>([Atom.p1, Atom.p2]))
                Bind(Reg, to: Set<Atom>([Atom.r1]))
                Bind(Adr, to: Set<Atom>([Atom.a1]))
                Bind(Val, to: Set<Atom>([Atom.v1, Atom.v2]))
                Bind(InitWr, to: Atom.initWr)
                Bind(MaxQLen, to: 1)
            }
        }
    }
}

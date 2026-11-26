// Reads and writes of a register are placed in a serial order between issue and completion.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/AdvancedExamples/InnerSerial.tla

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
    private enum Step: String, CaseIterable {
        case issueRequest = "IssueRequest"
        case completeWrite = "RespondToWr"
        case completeRead = "RespondToRd"
        case extendOperationOrder = "Internal"
    }
    package static var spec: TLASpec {
        #spec("MCInnerSerial") { scope in
            Extends(.naturals, .sequences, .finiteSets)
            let processes = scope.parameter(tlaName: "Proc", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.p1, Atom.p2])))
            let registers = scope.parameter(tlaName: "Reg", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.r1])))
            let addresses = scope.parameter(tlaName: "Adr", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.a1])))
            let values = scope.parameter(tlaName: "Val", as: Set<Atom>.self, in: Subsets(of: Set<Atom>([Atom.v1, Atom.v2])))
            let initialWrite = scope.parameter(tlaName: "InitWr_1", as: Atom.self, in: Set<Atom>([Atom.initWr]))
            let maxQueueLength = scope.parameter(tlaName: "MaxQLen", as: Int.self, in: 1...1)
            let free = addresses.flatMapping { a in values.mapping { v in RegisterValue.expression(adr: a, val: v, op: "Free") } }
            let requests = addresses.flatMapping { a in values.flatMapping { v in
                Set<String>(["Rd", "Wr"]).mapping { op in RegisterValue.expression(adr: a, val: v, op: op) }
            } }
            let registerFile = scope.sharedVar(tlaName: "regFile", initiallyIn: Functions(from: processes, to: Functions(from: registers, to: free)))
            let operationQueues = scope.sharedVar(tlaName: "opQ", initial: Dictionary<Atom, [QueueEntry]>.mapping(over: processes) { _ in [QueueEntry]() })
            let operationOrder = scope.sharedVar(tlaName: "opOrder", initial: Set<TupleExpr<OperationID>>())
            let extendOperationOrder = Macro {
                let ids = processes.flatMapping { p in
                    IntRange(1, through: operationQueues[p].count).mapping { i in OperationID.expression(proc: p, idx: i) }
                }
                let edges = ids.flatMapping { i in ids.mapping { j in TupleExpr<OperationID>.literal(i, j) } }
                let requestsAfter = Dictionary<OperationID, RegisterValue>.mapping(over: ids) { i in
                    If(operationQueues[i.proc][i.idx].recordFields.contains("source"),
                        then: operationQueues[i.proc][i.idx].assuming(ReadOperation.self).req,
                        else: operationQueues[i.proc][i.idx].assuming(Operation.self).req)
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
                    let reads = ids.filter { i in operationQueues[i.proc][i.idx].recordFields.contains("source") }
                    When(reads.allSatisfy { i in
                        !ids.contains { j in
                            requestsAfter[j].op == "Wr" && requestsAfter[j].adr == requestsAfter[i].adr
                                && total.contains(TupleExpr<OperationID>.literal(j, i))
                                && (operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source == Origin.second(initialWrite)
                                    || ids.contains { sourceID in
                                        sourceID.proc == operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).proc
                                            && sourceID.idx == operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).idx
                                            && total.contains(TupleExpr<OperationID>.literal(sourceID, j))
                                    })
                        }
                    })
                    When(operationOrder.isSubset(of: total))
                    With(Subsets(of: total)) { candidate in
                        When(operationOrder.isSubset(of: candidate))
                        operationOrder.set(candidate)
                    }
                }
            }
            let operationIDs = processes.flatMapping { p in
                IntRange(1, through: operationQueues[p].count).mapping { idx in OperationID.expression(proc: p, idx: idx) }
            }
            let requestAt = Dictionary<OperationID, RegisterValue>.mapping(over: operationIDs) { i in
                If(operationQueues[i.proc][i.idx].recordFields.contains("source"),
                    then: operationQueues[i.proc][i.idx].assuming(ReadOperation.self).req,
                    else: operationQueues[i.proc][i.idx].assuming(Operation.self).req)
            }
            let registerAt = Dictionary<OperationID, Atom>.mapping(over: operationIDs) { i in
                If(operationQueues[i.proc][i.idx].recordFields.contains("source"),
                    then: operationQueues[i.proc][i.idx].assuming(ReadOperation.self).reg,
                    else: operationQueues[i.proc][i.idx].assuming(Operation.self).reg)
            }
            let initialValue = Select(from: values) { _ in true }
            Do(Step.issueRequest, over: processes, requests, registers) { proc, req, reg in
                When(registerFile[proc][reg].op == "Free")
                let queued = operationQueues[proc].appending(QueueEntry.first(Operation.expression(req: req, reg: reg)))
                registerFile[proc][reg].set(req)
                operationQueues[proc].set(queued)
                extendOperationOrder()
            }
            let completeWrite = Do(Step.completeWrite, over: processes, registers) { proc, reg in
                When(registerFile[proc][reg].op == "Wr")
                let idx = Select(from: IntRange(1, through: operationQueues[proc].count)) { i in
                    registerAt[OperationID.expression(proc: proc, idx: i)] == reg
                }
                let id = OperationID.expression(proc: proc, idx: idx)
                let done = QueueEntry.first(Operation.expression(req: RegisterValue.expression(adr: requestAt[id].adr, val: requestAt[id].val, op: requestAt[id].op), reg: Atom.done))
                let queue = SequenceMapping(length: operationQueues[proc].count) { i in If(i == idx, then: done, else: operationQueues[proc][i]) }
                registerFile[proc][reg].op.set("Free")
                operationQueues[proc].set(queue)
                extendOperationOrder()
            }
            let completeRead = Do(Step.completeRead, over: processes, registers) { proc, reg in
                let req = registerFile[proc][reg]
                When(req.op == "Rd")
                let idx = Select(from: IntRange(1, through: operationQueues[proc].count)) { i in
                    registerAt[OperationID.expression(proc: proc, idx: i)] == reg
                }
                let writes = operationIDs.filter { w in requestAt[w].op == "Wr" && requestAt[w].adr == req.adr }
                let sources = writes.mapping { w in Origin.first(w) }.inserting(Origin.second(initialWrite))
                With(sources) { src in
                    let val = If(src == Origin.second(initialWrite), then: initialValue,
                        else: requestAt[Select(from: writes) { w in w.proc == src.assuming(OperationID.self).proc && w.idx == src.assuming(OperationID.self).idx }].val)
                    let reply = RegisterValue.expression(adr: req.adr, val: val, op: "Rd")
                    let done = QueueEntry.second(ReadOperation.expression(req: reply, reg: Atom.done, source: src))
                    let queue = SequenceMapping(length: operationQueues[proc].count) { i in If(i == idx, then: done, else: operationQueues[proc][i]) }
                    registerFile[proc][reg].val.set(val)
                    registerFile[proc][reg].op.set("Free")
                    operationQueues[proc].set(queue)
                    extendOperationOrder()
                }
            }
            let extendOrder = Do(Step.extendOperationOrder) { extendOperationOrder() }
            // With two processes and one queue entry each, a nonstuttering Internal step
            // orders their two live IDs. Every other distinct-ID pair is disabled.
            WeakFairness(extendOrder)
            WeakFairness(eachOf: [completeRead, completeWrite])
            let registerValues = free.union(requests)
            let completedReads = operationIDs.filter { i in operationQueues[i.proc][i.idx].recordFields.contains("source") }
            Invariant("DataInvariant") {
                registerFile.keys == processes && operationQueues.keys == processes
                    && processes.allSatisfy { p in registerFile[p].keys == registers
                        && registers.allSatisfy { r in registerValues.contains(registerFile[p][r])
                            && operationIDs.filter { i in i.proc == p && registerAt[i] == r }.count
                                == If(registerFile[p][r].op == "Free", then: 0, else: 1)
                        }
                    }
                    && operationOrder.allSatisfy { edge in
                        edge.count == 2 && operationIDs.contains(edge[1]) && operationIDs.contains(edge[2])
                    }
                    && operationIDs.allSatisfy { i in
                        addresses.contains(requestAt[i].adr) && values.contains(requestAt[i].val)
                            && Set<String>(["Rd", "Wr"]).contains(requestAt[i].op)
                            && If(registerAt[i] == Atom.done,
                                then: If(completedReads.contains(i), then: requestAt[i].op == "Rd", else: requestAt[i].op == "Wr"),
                                else: registers.contains(registerAt[i]) && !completedReads.contains(i)
                                    && registerFile[i.proc][registerAt[i]].adr == requestAt[i].adr
                                    && registerFile[i.proc][registerAt[i]].op == requestAt[i].op
                                    && registerFile[i.proc][registerAt[i]].val == requestAt[i].val)
                    }
                    && completedReads.allSatisfy { i in
                        If(operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source == Origin.second(initialWrite),
                            then: requestAt[i].val == initialValue,
                            else: operationIDs.contains { w in
                                w.proc == operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).proc
                                    && w.idx == operationQueues[i.proc][i.idx].assuming(ReadOperation.self).source.assuming(OperationID.self).idx
                                    && requestAt[w].op == "Wr" && requestAt[w].adr == requestAt[i].adr
                                    && requestAt[w].val == requestAt[i].val
                            })
                    }
            }
            Constraint(processes.allSatisfy { p in operationQueues[p].count <= maxQueueLength })
            // Index -1 identifies a register obligation. MCNat starts at zero.
            let slots = processes.flatMapping { p in registers.mapping { r in ResponseSubject.expression(proc: p, reg: r, idx: -1) } }
            let subjects = slots.union(processes.flatMapping { p in
                IntRange(0, through: maxQueueLength).mapping { i in ResponseSubject.expression(proc: p, reg: p, idx: i) }
            })
            let completedIDs = operationIDs.filter { i in registerAt[i] == Atom.done }
            let AlwaysResponds = Temporal()
            AlwaysResponds(forEach: subjects) { s in
                .conditional(s.idx == -1,
                    then: .leadsTo(registerFile[s.proc][s.reg].op != "Free", registerFile[s.proc][s.reg].op == "Free"),
                    else: .leadsTo(operationIDs.contains(OperationID.expression(proc: s.proc, idx: s.idx)),
                        completedIDs.contains(OperationID.expression(proc: s.proc, idx: s.idx))))
            }
            Validation("Upstream") {
                Bind(processes, to: Set<Atom>([Atom.p1, Atom.p2]))
                Bind(registers, to: Set<Atom>([Atom.r1]))
                Bind(addresses, to: Set<Atom>([Atom.a1]))
                Bind(values, to: Set<Atom>([Atom.v1, Atom.v2]))
                Bind(initialWrite, to: Atom.initWr)
                Bind(maxQueueLength, to: 1)
            }
        }
    }
}

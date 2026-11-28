// Extra lock-acquisition steps expose intermediate states used to relate the lock to Peterson’s
// algorithm.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/locks_auxiliary_vars/LockHS.tla

import SwiftTLA
import SwiftTLAMacros

/// Lock acquisition takes two extra steps so observers can also see Peterson's intermediate states.
@TLAModel
package struct LockHSModel: Sendable {
    package struct Idle: Hashable, Sendable { package let top: String }
    package struct Pending: Hashable, Sendable {
        package let id: String
        package let ctxt: Int
        package let val: Int
    }
    package typealias Stutter = OneOf<Idle, Pending>
    private enum Step: String, CaseIterable {
        case advanceOutsideAcquisition = "NoStutter"
        case acquireLockOrAdvanceHistory = "l1HS"
    }

    package static var spec: TLASpec {
        #spec("LockHS") { scope in
            let processes = IntRange(1, through: 2)
            let pc = scope.sharedVar(initial: Dictionary<Int, String>.mapping(over: processes) { _ in "l0" })
            let lock = scope.sharedVar(initial: 1)
            let h_turn = scope.sharedVar(initial: 1)
            let s = scope.sharedVar(initiallyIn: Set<Stutter>([Stutter.first(Idle(top: "top"))]))
            let idle = s == Stutter.first(Idle(top: "top"))
            let pending = s.assuming(Pending.self)

            Do(Step.advanceOutsideAcquisition, when: idle) {
                With(processes) { process in
                    When(pc[process] == "l0" || pc[process] == "cs" || pc[process] == "l2")
                    If(pc[process] == "l0") {
                        pc[process].set("l1")
                    } else: {
                        If(pc[process] == "cs") {
                            pc[process].set("l2")
                        } else: {
                            lock.set(1)
                            pc[process].set("l0")
                        }
                    }
                }
            }
            Do(Step.acquireLockOrAdvanceHistory, over: processes) { process in
                If(idle) {
                    When(pc[process] == "l1" && lock == 1)
                    lock.set(0)
                    pc[process].set("cs")
                    Assign(s, to: Stutter.second(Pending.expression(id: "l1", ctxt: process, val: 2)))
                } else: {
                    When(pending.id == "l1" && pending.ctxt == process)
                    If(pending.val == 1) {
                        Assign(s, to: Stutter.first(Idle(top: "top")))
                    } else: {
                        If(pending.val == 2) { h_turn.set(3 - process) }
                        Assign(s, to: Stutter.second(Pending.expression(id: "l1", ctxt: process, val: pending.val - 1)))
                    }
                }
            }

            let holders = processes.filter { process in pc[process] == "cs" || pc[process] == "l2" }
            Invariant("LockInv") {
                holders.count <= 1
                holders.isEmpty || lock == 0
            }
            Invariant("TypeOKHS") {
                (0...1).contains(lock)
                processes.contains(h_turn)
                pc.keys == processes
                processes.allSatisfy { process in Set<String>(["l0", "l1", "cs", "l2"]).contains(pc[process]) }
                idle || (pending.id == "l1" && processes.contains(pending.ctxt) && (1...2).contains(pending.val))
            }
            Invariant("InvHS") {
                processes.allSatisfy { process in
                    let waiting = !idle && pending.ctxt == process
                    let mustYield = pc[process] == "l2" || (pc[process] == "cs" && idle) || (waiting && pending.val == 1)
                    return (!waiting || pc[process] == "cs") && (!mustYield || h_turn == 3 - process)
                }
            }
            let L = Instance(of: LockModel.self) {}
            Refinement("Spec", instance: L) {
                Map(\.lock, from: lock)
                Map(\.pc, projecting: pc)
            }

            let translatedPC = Dictionary<Int, String>.mapping(over: processes) { process in
                let label = pc[process]
                let inside = If(idle, then: "cs", else: If(pending.ctxt != process, then: "cs", else:
                    If(pending.val == 2, then: "a2", else: If(pending.val == 1, then: "a3", else: "error"))))
                return If(label == "l0", then: "a0", else: If(label == "l1", then: "a1", else:
                    If(label == "l2", then: "a4", else: inside)))
            }
            let flags = Dictionary<Int, Bool>.mapping(over: processes) { process in
                Set<String>(["a2", "a3", "cs", "a4"]).contains(translatedPC[process])
            }
            let P = Instance(of: PetersonModel.self) {}
            Refinement("PSpec", instance: P) {
                Map(\.c, projecting: flags)
                Map(\.turn, projecting: h_turn)
                Map(\.pc, projecting: translatedPC)
            }
            Validation("published", label: "LockHS") {}
        }
    }
}

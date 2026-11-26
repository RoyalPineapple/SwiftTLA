// Two gates and a shared counter implement a reusable barrier for a group of processes.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/barriers/Barriers.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BarriersModel: Sendable {
    private enum Step: String, CaseIterable {
        case a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12
    }

    package static var spec: TLASpec {
        #spec("Barriers") { scope in
            Extends(.integers, .finiteSets)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let processes = IntRange(1, through: N)
            let gate_2 = scope.sharedVar(initial: 0)
            let TypeOK = Invariant()
            let LockInv = Invariant()
            let Inv = Invariant()
            let FlushInv = Invariant()

            let barriers = Algorithm { scope in
                let lock = scope.sharedVar(initial: 1)
                let gate_1 = scope.sharedVar(initial: 0)
                let rdv = scope.sharedVar(initial: 0)

                Each(processes) { process in
                    Do(Step.a0) { Skip() }
                    Do(Step.a1) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.a2) { rdv += 1 }
                    Do(Step.a3) {
                        If(rdv == N) { Goto(Step.a4) } else: { Goto(Step.a5) }
                    }
                    Do(Step.a4) { gate_1 += N }
                    Do(Step.a5) { lock.set(1) }
                    Do(Step.a6) {
                        When(gate_1 > 0)
                        gate_1.set(gate_1 - 1)
                    }
                    Do(Step.a7) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.a8) { rdv.set(rdv - 1) }
                    Do(Step.a9) {
                        If(rdv == 0) { Goto(Step.a10) } else: { Goto(Step.a11) }
                    }
                    Do(Step.a10) { gate_2 += N }
                    Do(Step.a11) { lock.set(1) }
                    Do(Step.a12) {
                        When(gate_2 > 0)
                        gate_2.set(gate_2 - 1)
                        Goto(Step.a0)
                    }
                }

                TypeOK {
                    (0...1).contains(lock)
                    gate_1 >= 0
                    gate_2 >= 0
                    Int.all.contains(rdv)
                    processes.allSatisfy { p in
                        p.isAt(anyOf: Step.a0, .a1, .a2, .a3, .a4, .a5, .a6, .a7, .a8, .a9, .a10, .a11, .a12)
                    }
                }
                let critical = processes.filter { p in p.isAt(anyOf: Step.a2, .a3, .a4, .a5, .a8, .a9, .a10, .a11) }
                LockInv {
                    critical.count <= 1
                    critical.isEmpty || lock == 0
                }
                let firstChamber = processes.filter { p in p.isAt(anyOf: Step.a0, .a1, .a2, .a3, .a4, .a5, .a6) }
                let secondChamber = processes.filter { p in p.isAt(anyOf: Step.a7, .a8, .a9, .a10, .a11, .a12) }
                let enteringFirst = processes.contains { p in p.isAt(anyOf: Step.a0, .a1, .a2, .a3, .a4) }
                let enteringSecond = processes.contains { p in p.isAt(anyOf: Step.a7, .a8, .a9, .a10) }
                Inv {
                    IntRange(0, through: N).contains(gate_1)
                    IntRange(0, through: N).contains(gate_2)
                    rdv == processes.filter { p in p.isAt(anyOf: Step.a3, .a4, .a5, .a6, .a7, .a8) }.count
                    gate_1 <= 0 || processes.contains { p in p.isAt(anyOf: Step.a5, .a6) }
                    gate_2 <= 0 || processes.contains { p in p.isAt(anyOf: Step.a11, .a12) }
                    gate_1 == 0 || gate_2 == 0
                    !enteringFirst || !enteringSecond
                    gate_1 <= firstChamber.count
                    !enteringFirst || gate_1 == 0
                    processes.allSatisfy { p in
                        !p.isAt(anyOf: Step.a4) || (rdv == N && processes.allSatisfy { q in p == q || q.isAt(anyOf: Step.a6) })
                    }
                    gate_2 <= secondChamber.count
                    !enteringSecond || gate_2 == 0
                    processes.allSatisfy { p in
                        !p.isAt(anyOf: Step.a10) || (rdv == 0 && processes.allSatisfy { q in p == q || q.isAt(anyOf: Step.a12) })
                    }
                }
                FlushInv {
                    gate_1 <= 0 || gate_1 == firstChamber.count
                    gate_2 <= 0 || gate_2 == secondChamber.count
                }
            }
            barriers
            let abstract = Instance(of: BarrierModel.self) { Bind(\.N, to: N) }
            abstract
            let translatedPC = Dictionary<Int, String>.mapping(over: processes) { p in
                If(p.isAt(anyOf: Step.a1, .a2, .a3, .a4, .a5, .a6, .a7, .a8, .a9, .a10), then: "b1", else:
                    If(p.isAt(anyOf: Step.a0) || gate_2 > 0, then: "b0", else: "b1"))
            }
            let BSpec = Refinement(instance: abstract) { Map(\.pc, projecting: translatedPC) }
            BSpec
            Validation("published") { Bind(N, to: 6) }
        }
    }
}

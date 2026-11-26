// Two gates and a shared counter implement a reusable barrier for a group of processes.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/barriers/Barriers.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BarriersModel: Sendable {
    private enum Step: String, CaseIterable {
        case startBarrierRound = "a0"
        case lockForArrival = "a1"
        case countArrival = "a2"
        case checkForLastArrival = "a3"
        case openFirstGate = "a4"
        case unlockAfterArrival = "a5"
        case passFirstGate = "a6"
        case lockForDeparture = "a7"
        case countDeparture = "a8"
        case checkForLastDeparture = "a9"
        case openSecondGate = "a10"
        case unlockAfterDeparture = "a11"
        case passSecondGate = "a12"
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

            Algorithm("barriers") { scope in
                let lock = scope.sharedVar(initial: 1)
                let gate_1 = scope.sharedVar(initial: 0)
                let rdv = scope.sharedVar(initial: 0)

                Each(processes) { process in
                    Do(Step.startBarrierRound) { Skip() }
                    Do(Step.lockForArrival) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.countArrival) { rdv += 1 }
                    Do(Step.checkForLastArrival) {
                        If(rdv == N) { Goto(Step.openFirstGate) } else: { Goto(Step.unlockAfterArrival) }
                    }
                    Do(Step.openFirstGate) { gate_1 += N }
                    Do(Step.unlockAfterArrival) { lock.set(1) }
                    Do(Step.passFirstGate) {
                        When(gate_1 > 0)
                        gate_1.set(gate_1 - 1)
                    }
                    Do(Step.lockForDeparture) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.countDeparture) { rdv.set(rdv - 1) }
                    Do(Step.checkForLastDeparture) {
                        If(rdv == 0) { Goto(Step.openSecondGate) } else: { Goto(Step.unlockAfterDeparture) }
                    }
                    Do(Step.openSecondGate) { gate_2 += N }
                    Do(Step.unlockAfterDeparture) { lock.set(1) }
                    Do(Step.passSecondGate) {
                        When(gate_2 > 0)
                        gate_2.set(gate_2 - 1)
                        Goto(Step.startBarrierRound)
                    }
                }

                TypeOK {
                    (0...1).contains(lock)
                    gate_1 >= 0
                    gate_2 >= 0
                    Int.all.contains(rdv)
                    processes.allSatisfy { process in
                        process.isAt(anyOf:
                            Step.startBarrierRound, .lockForArrival, .countArrival,
                            .checkForLastArrival, .openFirstGate, .unlockAfterArrival,
                            .passFirstGate, .lockForDeparture, .countDeparture,
                            .checkForLastDeparture, .openSecondGate, .unlockAfterDeparture,
                            .passSecondGate
                        )
                    }
                }
                let lockHolders = processes.filter { process in
                    process.isAt(anyOf:
                        Step.countArrival, .checkForLastArrival, .openFirstGate,
                        .unlockAfterArrival, .countDeparture, .checkForLastDeparture,
                        .openSecondGate, .unlockAfterDeparture
                    )
                }
                LockInv {
                    lockHolders.count <= 1
                    lockHolders.isEmpty || lock == 0
                }
                let firstChamber = processes.filter { process in
                    process.isAt(anyOf:
                        Step.startBarrierRound, .lockForArrival, .countArrival,
                        .checkForLastArrival, .openFirstGate, .unlockAfterArrival, .passFirstGate
                    )
                }
                let secondChamber = processes.filter { process in
                    process.isAt(anyOf:
                        Step.lockForDeparture, .countDeparture, .checkForLastDeparture,
                        .openSecondGate, .unlockAfterDeparture, .passSecondGate
                    )
                }
                let enteringFirst = processes.contains { process in
                    process.isAt(anyOf:
                        Step.startBarrierRound, .lockForArrival, .countArrival,
                        .checkForLastArrival, .openFirstGate
                    )
                }
                let enteringSecond = processes.contains { process in
                    process.isAt(anyOf:
                        Step.lockForDeparture, .countDeparture, .checkForLastDeparture,
                        .openSecondGate
                    )
                }
                let arrivedProcesses = processes.filter { process in
                    process.isAt(anyOf:
                        Step.checkForLastArrival, .openFirstGate, .unlockAfterArrival,
                        .passFirstGate, .lockForDeparture, .countDeparture
                    )
                }
                Inv {
                    IntRange(0, through: N).contains(gate_1)
                    IntRange(0, through: N).contains(gate_2)
                    rdv == arrivedProcesses.count
                    gate_1 <= 0 || processes.contains { process in
                        process.isAt(anyOf: Step.unlockAfterArrival, .passFirstGate)
                    }
                    gate_2 <= 0 || processes.contains { process in
                        process.isAt(anyOf: Step.unlockAfterDeparture, .passSecondGate)
                    }
                    gate_1 == 0 || gate_2 == 0
                    !enteringFirst || !enteringSecond
                    gate_1 <= firstChamber.count
                    !enteringFirst || gate_1 == 0
                    processes.allSatisfy { process in
                        !process.isAt(anyOf: Step.openFirstGate)
                            || (rdv == N && processes.allSatisfy { other in
                                process == other || other.isAt(anyOf: Step.passFirstGate)
                            })
                    }
                    gate_2 <= secondChamber.count
                    !enteringSecond || gate_2 == 0
                    processes.allSatisfy { process in
                        !process.isAt(anyOf: Step.openSecondGate)
                            || (rdv == 0 && processes.allSatisfy { other in
                                process == other || other.isAt(anyOf: Step.passSecondGate)
                            })
                    }
                }
                FlushInv {
                    gate_1 <= 0 || gate_1 == firstChamber.count
                    gate_2 <= 0 || gate_2 == secondChamber.count
                }
            }
            let abstract = Instance(of: BarrierModel.self) { Bind(\.N, to: N) }
            let translatedPC = Dictionary<Int, String>.mapping(over: processes) { process in
                If(process.isAt(anyOf:
                    Step.lockForArrival, .countArrival, .checkForLastArrival, .openFirstGate,
                    .unlockAfterArrival, .passFirstGate, .lockForDeparture, .countDeparture,
                    .checkForLastDeparture, .openSecondGate
                ), then: "b1", else:
                    If(process.isAt(anyOf: Step.startBarrierRound) || gate_2 > 0, then: "b0", else: "b1"))
            }
            Refinement("BSpec", instance: abstract) { Map(\.pc, projecting: translatedPC) }
            Validation("published") { Bind(N, to: 6) }
        }
    }
}

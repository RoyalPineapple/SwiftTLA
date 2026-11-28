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
            let processCount = scope.parameter(tlaName: "N", as: Int.self, in: Int.all)
            Assume(processCount > 0)
            let processes = IntRange(1, through: processCount)
            let secondGatePermits = scope.sharedVar(tlaName: "gate_2", initial: 0)
            let TypeOK = Invariant()
            let LockInv = Invariant()
            let Inv = Invariant()
            let FlushInv = Invariant()

            Algorithm("barriers") { scope in
                let lock = scope.sharedVar(initial: 1)
                let firstGatePermits = scope.sharedVar(tlaName: "gate_1", initial: 0)
                let arrivalCount = scope.sharedVar(tlaName: "rdv", initial: 0)

                Each(processes) { process in
                    Do(Step.startBarrierRound) { Skip() }
                    Do(Step.lockForArrival) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.countArrival) { arrivalCount += 1 }
                    Do(Step.checkForLastArrival) {
                        If(arrivalCount == processCount) { Goto(Step.openFirstGate) } else: { Goto(Step.unlockAfterArrival) }
                    }
                    Do(Step.openFirstGate) { firstGatePermits += processCount }
                    Do(Step.unlockAfterArrival) { lock.set(1) }
                    Do(Step.passFirstGate) {
                        When(firstGatePermits > 0)
                        firstGatePermits.set(firstGatePermits - 1)
                    }
                    Do(Step.lockForDeparture) {
                        When(lock == 1)
                        lock.set(0)
                    }
                    Do(Step.countDeparture) { arrivalCount.set(arrivalCount - 1) }
                    Do(Step.checkForLastDeparture) {
                        If(arrivalCount == 0) { Goto(Step.openSecondGate) } else: { Goto(Step.unlockAfterDeparture) }
                    }
                    Do(Step.openSecondGate) { secondGatePermits += processCount }
                    Do(Step.unlockAfterDeparture) { lock.set(1) }
                    Do(Step.passSecondGate) {
                        When(secondGatePermits > 0)
                        secondGatePermits.set(secondGatePermits - 1)
                        Goto(Step.startBarrierRound)
                    }
                }

                TypeOK {
                    (0...1).contains(lock)
                    firstGatePermits >= 0
                    secondGatePermits >= 0
                    Int.all.contains(arrivalCount)
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
                    IntRange(0, through: processCount).contains(firstGatePermits)
                    IntRange(0, through: processCount).contains(secondGatePermits)
                    arrivalCount == arrivedProcesses.count
                    firstGatePermits <= 0 || processes.contains { process in
                        process.isAt(anyOf: Step.unlockAfterArrival, .passFirstGate)
                    }
                    secondGatePermits <= 0 || processes.contains { process in
                        process.isAt(anyOf: Step.unlockAfterDeparture, .passSecondGate)
                    }
                    firstGatePermits == 0 || secondGatePermits == 0
                    !enteringFirst || !enteringSecond
                    firstGatePermits <= firstChamber.count
                    !enteringFirst || firstGatePermits == 0
                    processes.allSatisfy { process in
                        !process.isAt(anyOf: Step.openFirstGate)
                            || (arrivalCount == processCount && processes.allSatisfy { other in
                                process == other || other.isAt(anyOf: Step.passFirstGate)
                            })
                    }
                    secondGatePermits <= secondChamber.count
                    !enteringSecond || secondGatePermits == 0
                    processes.allSatisfy { process in
                        !process.isAt(anyOf: Step.openSecondGate)
                            || (arrivalCount == 0 && processes.allSatisfy { other in
                                process == other || other.isAt(anyOf: Step.passSecondGate)
                            })
                    }
                }
                FlushInv {
                    firstGatePermits <= 0 || firstGatePermits == firstChamber.count
                    secondGatePermits <= 0 || secondGatePermits == secondChamber.count
                }
            }
            let abstract = Instance(of: BarrierModel.self) { Bind(\.N, to: processCount) }
            let translatedPC = Dictionary<Int, String>.mapping(over: processes) { process in
                If(process.isAt(anyOf:
                    Step.lockForArrival, .countArrival, .checkForLastArrival, .openFirstGate,
                    .unlockAfterArrival, .passFirstGate, .lockForDeparture, .countDeparture,
                    .checkForLastDeparture, .openSecondGate
                ), then: "b1", else:
                    If(process.isAt(anyOf: Step.startBarrierRound) || secondGatePermits > 0, then: "b0", else: "b1"))
            }
            Refinement("BSpec", instance: abstract) { Map(\.pc, projecting: translatedPC) }
            Validation("published") { Bind(processCount, to: 6) }
        }
    }
}

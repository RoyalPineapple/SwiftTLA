// Two processes use flags and a turn variable to coordinate entry to a critical section.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/locks_auxiliary_vars/Peterson.tla

import SwiftTLA
import SwiftTLAMacros

/// Peterson's two-process mutual-exclusion algorithm from the upstream
/// PlusCal auxiliary-variables collection.
@TLAModel
package struct PetersonModel: ParameterlessGeneratedModel {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case noncriticalSection = "a0"
        case raiseInterestFlag = "a1"
        case giveOtherProcessPriority = "a2"
        case awaitPermissionToEnter = "a3"
        case criticalSection = "cs"
        case clearInterestFlag = "a4"
    }

    package static var spec: TLASpec {
        #spec("Peterson") {
            Extends(.integers)
            let TypeOK = Invariant()
            let Inv = Invariant()
            Algorithm("Peterson") { scope in
                let c = scope.sharedVar(initial: Function<Process, Bool>.literal(
                    (.one, false), (.two, false)
                ))
                let turn = scope.sharedVar(initial: Process.one)

                Each(Process.all) { process in
                    Do(Step.noncriticalSection) {
                        Skip()
                    }
                    Do(Step.raiseInterestFlag) {
                        c.set(c.updating(process, to: true))
                    }
                    Do(Step.giveOtherProcessPriority) {
                        turn.set(If(
                            process == .one,
                            then: Process.two,
                            else: Process.one
                        ))
                    }
                    Do(Step.awaitPermissionToEnter) {
                        Let(If(
                                process == .one,
                                then: Process.two,
                                else: Process.one
                            )) { other in
                            When(c[other] == false || turn == process)
                        }
                    }
                    Do(Step.criticalSection) {
                        Skip()
                    }
                    Do(Step.clearInterestFlag) {
                        c.set(c.updating(process, to: false))
                        Goto(Step.noncriticalSection)
                    }
                }

                TypeOK {
                    Process.all.contains(turn)
                    Process.all.allSatisfy { process in
                        (c[process] == false || c[process] == true)
                            && process.isAt(anyOf: Step.noncriticalSection, .raiseInterestFlag, .giveOtherProcessPriority, .awaitPermissionToEnter, .criticalSection, .clearInterestFlag)
                    }
                }

                let holders = Process.all.filter { process in process.isAt(anyOf: Step.criticalSection, .clearInterestFlag) }
                Inv {
                    Process.all.allSatisfy { process in
                        c[process] == process.isAt(anyOf: Step.giveOtherProcessPriority, .awaitPermissionToEnter, .criticalSection, .clearInterestFlag)
                    }
                    Process.all.allSatisfy { process in
                        !process.isAt(anyOf: Step.criticalSection, .clearInterestFlag) || turn == process
                            || If(process == .one, then: Process.two, else: Process.one)
                                .isAt(anyOf: Step.noncriticalSection, .raiseInterestFlag, .giveOtherProcessPriority)
                    }
                    holders.count <= 1
                }
            }
            let L = Instance(of: LockModel.self) {}
            let lockPC = Dictionary<Process, String>.mapping(over: Process.all) { process in
                If(process.isAt(anyOf: Step.noncriticalSection), then: "l0", else:
                    If(process.isAt(anyOf: Step.raiseInterestFlag, .giveOtherProcessPriority, .awaitPermissionToEnter), then: "l1", else:
                        If(process.isAt(anyOf: Step.criticalSection), then: "cs", else: "l2")))
            }
            let held = Process.all.contains { process in process.isAt(anyOf: Step.criticalSection, .clearInterestFlag) }
            Refinement("LSpec", instance: L) {
                Map(\.lock, from: If(held, then: 0, else: 1))
                Map(\.pc, projecting: lockPC)
            }
            Validation("safety", label: "PetersonSafety") {}.checking(only: [TypeOK, Inv])
            Validation("published", label: "Peterson") {}
        }
    }
}

extension Example {
    package static let petersonTwoProcess = FiniteModelFixture(
        expectedDistinct: 42,
        maximumStateLimit: 50_000,
        spec: PetersonModel.spec,
    )
}

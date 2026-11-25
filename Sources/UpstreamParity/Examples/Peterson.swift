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
        case a0
        case a1
        case a2
        case a3
        case cs
        case a4
    }

    package static var spec: TLASpec {
        #spec("Peterson") {
            Extends(.integers)
            let TypeOK = Invariant()
            let Inv = Invariant()
            let Peterson = Algorithm { scope in
                let c = scope.sharedVar(initial: Function<Process, Bool>.literal(
                    (.one, false), (.two, false)
                ))
                let turn = scope.sharedVar(initial: Process.one)

                Each(Process.all) { process in
                    Do(Step.a0) {
                        Skip()
                    }
                    Do(Step.a1) {
                        c.set(c.updating(process, to: true))
                    }
                    Do(Step.a2) {
                        turn.set(If(
                            process == .one,
                            then: Process.two,
                            else: Process.one
                        ))
                    }
                    Do(Step.a3) {
                        Let(If(
                                process == .one,
                                then: Process.two,
                                else: Process.one
                            )) { other in
                            When(c[other] == false || turn == process)
                        }
                    }
                    Do(Step.cs) {
                        Skip()
                    }
                    Do(Step.a4) {
                        c.set(c.updating(process, to: false))
                        Goto(Step.a0)
                    }
                }

                TypeOK {
                    Process.all.contains(turn)
                    Process.all.allSatisfy { process in
                        (c[process] == false || c[process] == true)
                            && process.isAt(anyOf: Step.a0, .a1, .a2, .a3, .cs, .a4)
                    }
                }

                let holders = Process.all.filter { process in process.isAt(anyOf: Step.cs, .a4) }
                Inv {
                    Process.all.allSatisfy { process in
                        c[process] == process.isAt(anyOf: Step.a2, .a3, .cs, .a4)
                    }
                    Process.all.allSatisfy { process in
                        !process.isAt(anyOf: Step.cs, .a4) || turn == process
                            || If(process == .one, then: Process.two, else: Process.one)
                                .isAt(anyOf: Step.a0, .a1, .a2)
                    }
                    holders.count <= 1
                }
            }
            Peterson
            let L = Instance(of: LockModel.self) {}
            L
            let lockPC = Dictionary<Process, String>.mapping(over: Process.all) { process in
                If(process.isAt(anyOf: Step.a0), then: "l0", else:
                    If(process.isAt(anyOf: Step.a1, .a2, .a3), then: "l1", else:
                        If(process.isAt(anyOf: Step.cs), then: "cs", else: "l2")))
            }
            let held = Process.all.contains { process in process.isAt(anyOf: Step.cs, .a4) }
            let LSpec = Refinement(instance: L) {
                Map(\.lock, from: If(held, then: 0, else: 1))
                Map(\.pc, projecting: lockPC)
            }
            LSpec
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

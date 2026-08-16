import SwiftTLA
import SwiftTLAMacros

/// The upstream two-chamber barrier, expressed with the same PlusCal
/// statement macros (`Lock`, `Unlock`, `Wait`, and `Signal`) as its source.
@TLAModel
public struct BarriersN6Model {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case one = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5
        case six = 6

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.barriers.n6.process"
        )

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12
    }

    public static var spec: TLASpec {
        #spec("Barriers") {
            Extends("Integers")
            Algorithm("Barriers") {
                let lock = SharedVar(initial: 1)
                let gate1 = SharedVar(initial: 0)
                let gate2 = SharedVar(initial: 0)
                let rendezvous = SharedVar(initial: 0)

                let acquire = Macro { (lock: MacroParameter<Int>) in
                    Await(lock == 1)
                    Assign(lock, to: 0)
                }
                let release = Macro { (lock: MacroParameter<Int>) in
                    Assign(lock, to: 1)
                }
                let wait = Macro { (semaphore: MacroParameter<Int>) in
                    Await(semaphore > 0)
                    Assign(semaphore, to: semaphore - 1)
                }
                let signal = Macro { (semaphore: MacroParameter<Int>) in
                    Assign(semaphore, to: semaphore + 6)
                }

                Each(Process.all) { _ in
                    Do(Step.a0) { Skip() }
                    Do(Step.a1) { acquire(lock) }
                    Do(Step.a2) { Assign(rendezvous, to: rendezvous + 1) }
                    Do(Step.a3) {
                        If(rendezvous == 6) {
                            Goto(Step.a4)
                        } else: {
                            Goto(Step.a5)
                        }
                    }
                    Do(Step.a4) { signal(gate1) }
                    Do(Step.a5) { release(lock) }
                    Do(Step.a6) { wait(gate1) }
                    Do(Step.a7) { acquire(lock) }
                    Do(Step.a8) { Assign(rendezvous, to: rendezvous - 1) }
                    Do(Step.a9) {
                        If(rendezvous == 0) {
                            Goto(Step.a10)
                        } else: {
                            Goto(Step.a11)
                        }
                    }
                    Do(Step.a10) { signal(gate2) }
                    Do(Step.a11) { release(lock) }
                    Do(Step.a12) {
                        wait(gate2)
                        Goto(Step.a0)
                    }
                }

                Invariant("TypeOK") {
                    lock >= 0 && lock <= 1
                    gate1 >= 0 && gate1 <= 6
                    gate2 >= 0 && gate2 <= 6
                    rendezvous >= 0 && rendezvous <= 6
                }
            }
        }
    }
}

extension Example {
    public static let barriersN6 = Entry(
        id: "barriers/Barriers_N6",
        upstreamSpec: "barriers",
        upstreamModule: "specifications/barriers/Barriers.tla",
        upstreamCfg: "specifications/barriers/Barriers.cfg",
        expectedDistinct: 29_279,
        spec: BarriersN6Model.spec,
        notes: "N=6 two-chamber PlusCal barrier with typed statement-macro expansion."
    )
}

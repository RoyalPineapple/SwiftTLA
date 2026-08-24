import SwiftTLA
import SwiftTLAMacros

// Dining Philosophers — Chandy-Misra solution. NP=5.
// Upstream: specifications/DiningPhilosophers/DiningPhilosophers.tla

public struct DiningPhilosophersModel: Sendable {
    public enum Philosopher: Int, FiniteTLAValueDomain {
        case one = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5

        public static var defaultValue: Self { .one }
        public static let finiteValues: [Self] = [.one, .two, .three, .four, .five]

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public struct ForkFields {
        let holder: Philosopher
        let clean: Bool
    }

    public enum Fork: TLARecordSchema {
        public typealias Fields = ForkFields

        public static let fieldNames: Set<String> = ["holder", "clean"]
        public static let defaultRecord: TLAValue = .record(["holder": .int(1), "clean": .bool(false)])

        public static func fieldName<Value>(for field: KeyPath<ForkFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \ForkFields.holder { return "holder" }
            if key == \ForkFields.clean { return "clean" }
            return nil
        }

        public static let holder = field(\ForkFields.holder)
        public static let clean = field(\ForkFields.clean)
    }

    private enum Step: String, CaseIterable {
        case loop = "Loop"
        case think = "Think"
        case eat = "Eat"
    }

    public static var spec: TLASpec {
        #spec("DiningPhilosophers") {
            Extends(.integers)

            Algorithm("DiningPhilosophers", scoped: { scope in
                let forks = scope.sharedVar("forks", initial: Function<Philosopher, Record<Fork>>.literal(
                    (Philosopher.one, Record.literal(.init(Fork.holder, Philosopher.one), .init(Fork.clean, false))),
                    (Philosopher.two, Record.literal(.init(Fork.holder, Philosopher.one), .init(Fork.clean, false))),
                    (Philosopher.three, Record.literal(.init(Fork.holder, Philosopher.three), .init(Fork.clean, false))),
                    (Philosopher.four, Record.literal(.init(Fork.holder, Philosopher.four), .init(Fork.clean, false))),
                    (Philosopher.five, Record.literal(.init(Fork.holder, Philosopher.five), .init(Fork.clean, false)))
                ))

                Each(Philosopher.all, scoped: { philosopher, scope in
                    let hungry = scope.localVar("hungry", initial: true)

                    Do(Step.loop) {
                        let right = If(philosopher == Philosopher.one, then: Philosopher.two, else:
                            If(philosopher == Philosopher.two, then: Philosopher.three, else:
                                If(philosopher == Philosopher.three, then: Philosopher.four, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.five, else: Philosopher.one))))
                        let left = If(philosopher == Philosopher.one, then: Philosopher.five, else:
                            If(philosopher == Philosopher.two, then: Philosopher.one, else:
                                If(philosopher == Philosopher.three, then: Philosopher.two, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.three, else: Philosopher.four))))
                        let leftFork = forks[philosopher]
                        let rightFork = forks[right]
                        let canEat = leftFork[Fork.holder] == philosopher
                            && rightFork[Fork.holder] == philosopher
                            && leftFork[Fork.clean] == true
                            && rightFork[Fork.clean] == true

                        Either {
                            When(leftFork[Fork.holder] == philosopher && leftFork[Fork.clean] == false)
                            Assign(forks, to: forks.updating(
                                philosopher,
                                to: Record.literal(
                                    .init(Fork.holder, left),
                                    .init(Fork.clean, true)
                                )
                            ))
                        } or: {
                            Either {
                                When(
                                    rightFork[Fork.holder] == philosopher
                                        && rightFork[Fork.clean] == false
                                        && !(leftFork[Fork.holder] == philosopher && leftFork[Fork.clean] == false)
                                )
                                Assign(forks, to: forks.updating(
                                    right,
                                    to: Record.literal(
                                        .init(Fork.holder, right),
                                        .init(Fork.clean, true)
                                    )
                                ))
                            } or: {
                                When(
                                    !(leftFork[Fork.holder] == philosopher && leftFork[Fork.clean] == false)
                                        && !(rightFork[Fork.holder] == philosopher && rightFork[Fork.clean] == false)
                                )
                            }
                        }

                        Either {
                            When(canEat && hungry == true)
                            Goto(Step.eat)
                        } or: {
                            Either {
                                When(!canEat && hungry == true)
                                Goto(Step.loop)
                            } or: {
                                When(hungry == false)
                                Goto(Step.think)
                            }
                        }
                    }

                    Do(Step.think) {
                        Assign(hungry, to: true)
                        Goto(Step.loop)
                    }

                    Do(Step.eat) {
                        let right = If(philosopher == Philosopher.one, then: Philosopher.two, else:
                            If(philosopher == Philosopher.two, then: Philosopher.three, else:
                                If(philosopher == Philosopher.three, then: Philosopher.four, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.five, else: Philosopher.one))))
                        let leftFork = forks[philosopher]
                        let rightFork = forks[right]
                        Assign(hungry, to: false)
                        Assign(forks, to: forks
                            .updating(philosopher, to: leftFork.updating(Fork.clean, to: false))
                            .updating(right, to: rightFork.updating(Fork.clean, to: false))
                        )
                        Goto(Step.loop)
                    }

                    Invariant("TypeOK") {
                        (forks[philosopher][Fork.holder] == .one
                            || forks[philosopher][Fork.holder] == .two
                            || forks[philosopher][Fork.holder] == .three
                            || forks[philosopher][Fork.holder] == .four
                            || forks[philosopher][Fork.holder] == .five)
                            && (hungry == true || hungry == false)
                            && (At(Step.loop, philosopher) || At(Step.think, philosopher) || At(Step.eat, philosopher))
                    }
                })

                Invariant("ExclusiveAccess") {
                    All(Philosopher.all) { first in
                        All(Philosopher.all) { second in
                            first == second
                                || !(At(Step.eat, first) && At(Step.eat, second)
                                    && ((first == Philosopher.one && second == Philosopher.two)
                                        || (first == Philosopher.two && second == Philosopher.three)
                                        || (first == Philosopher.three && second == Philosopher.four)
                                        || (first == Philosopher.four && second == Philosopher.five)
                                        || (first == Philosopher.five && second == Philosopher.one)))
                        }
                    }
                }
            })
        }
    }
}

extension Example {
    static let diningPhilosophersNP5 = Example.Entry(
        id: "DiningPhilosophers/DiningPhilosophers",
        upstreamSpec: "DiningPhilosophers",
        upstreamModule: "specifications/DiningPhilosophers/DiningPhilosophers.tla",
        upstreamCfg: "specifications/DiningPhilosophers/DiningPhilosophers.cfg",
        expectedDistinct: 67,
        spec: DiningPhilosophersModel.spec,
        notes: "NP=5. Canonical PlusCal-shaped process model with typed fork records.",
    )
}
